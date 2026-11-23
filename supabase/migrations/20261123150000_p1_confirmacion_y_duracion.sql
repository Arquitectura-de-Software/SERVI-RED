-- =====================================================================
-- SERVI-RED | Persona 1 | Fase 4: Validación comunitaria y duración
-- Requisito 4: confirmacion_ciudadana, umbrales y cálculo de duración
-- =====================================================================

-- 1. Registrar confirmación ciudadana y evaluar umbral de transición
create or replace function public.registrar_confirmacion_ciudadana(
  p_incidente_id uuid,
  p_tipo public.tipo_confirmacion,
  p_lat double precision default null,
  p_lng double precision default null
)
returns table (
  confirmacion_id uuid,
  incidente_id uuid,
  estado_incidente public.estado_incidente,
  total_restablecido integer,
  total_sin_servicio integer,
  duracion_minutos integer,
  umbral_alcanzado boolean,
  mensaje text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_confirmacion_id uuid;
  v_ubicacion extensions.geography := null;
  v_estado_actual public.estado_incidente;
  v_nuevo_estado public.estado_incidente;
  v_inicio_en timestamptz;
  v_creado_en timestamptz;
  v_restablecido_en timestamptz;
  v_total_restablecido integer := 0;
  v_total_sin_servicio integer := 0;
  v_umbral integer := 3;
  v_umbral_alcanzado boolean := false;
  v_mensaje text;
  v_inicio_calculo timestamptz;
  v_fin_calculo timestamptz;
  v_duracion_segundos integer;
  v_duracion_minutos integer;
begin
  -- Validación de sesión ciudadana
  if auth.uid() is null or public.rol_actual() is distinct from 'ciudadano' then
    raise exception 'Se requiere una sesión ciudadana activa' using errcode = '42501';
  end if;

  if p_incidente_id is null or p_tipo is null then
    raise exception 'El incidente y el tipo de confirmación son obligatorios' using errcode = 'PT400';
  end if;

  -- Bloqueo y verificación de existencia del incidente
  select estado, inicio_en, creado_en, restablecido_en
  into v_estado_actual, v_inicio_en, v_creado_en, v_restablecido_en
  from public.incidente
  where id = p_incidente_id
  for update;

  if not found then
    raise exception 'Incidente % no encontrado', p_incidente_id using errcode = 'PT404';
  end if;

  -- Preparar ubicación si viene proporcionada
  if p_lat is not null and p_lng is not null
     and p_lat between -90 and 90 and p_lng between -180 and 180 then
    v_ubicacion := extensions.st_setsrid(
      extensions.st_makepoint(p_lng, p_lat), 4326
    )::extensions.geography;
  end if;

  -- Eliminar voto anterior opuesto para evitar contradicciones (un ciudadano solo tiene un estado activo por incidente)
  delete from public.confirmacion_ciudadana
  where incidente_id = p_incidente_id
    and ciudadano_id = auth.uid()
    and tipo <> p_tipo;

  -- Insertar o actualizar confirmación actual
  insert into public.confirmacion_ciudadana (
    incidente_id,
    ciudadano_id,
    tipo,
    ubicacion
  )
  values (
    p_incidente_id,
    auth.uid(),
    p_tipo,
    v_ubicacion
  )
  on conflict (incidente_id, ciudadano_id, tipo)
  do update set
    ubicacion = coalesce(excluded.ubicacion, confirmacion_ciudadana.ubicacion),
    creado_en = now()
  returning id into v_confirmacion_id;

  -- Contar totales comunitarios
  select count(*)::integer into v_total_restablecido
  from public.confirmacion_ciudadana
  where incidente_id = p_incidente_id and tipo = 'restablecido';

  select count(*)::integer into v_total_sin_servicio
  from public.confirmacion_ciudadana
  where incidente_id = p_incidente_id and tipo = 'sin_servicio';

  -- Evaluación de umbrales comunitarios
  v_nuevo_estado := v_estado_actual;

  if p_tipo = 'restablecido' and v_total_restablecido >= v_umbral and v_estado_actual = 'en_atencion' then
    update public.incidente
    set estado = 'restablecido',
        actualizado_en = now()
    where id = p_incidente_id
    returning estado, restablecido_en into v_nuevo_estado, v_restablecido_en;

    v_umbral_alcanzado := true;
    v_mensaje := 'Umbral de restablecimiento alcanzado (' || v_total_restablecido || ' confirmaciones). El incidente pasó a estado RESTABLECIDO.';

  elsif p_tipo = 'sin_servicio' and v_total_sin_servicio >= v_umbral and v_estado_actual = 'restablecido' then
    update public.incidente
    set estado = 'en_atencion',
        actualizado_en = now()
    where id = p_incidente_id
    returning estado, restablecido_en into v_nuevo_estado, v_restablecido_en;

    v_umbral_alcanzado := true;
    v_mensaje := 'Umbral de falla persistente alcanzado (' || v_total_sin_servicio || ' reportes sin servicio). El incidente se REABRIÓ a en_atención.';

  else
    v_umbral_alcanzado := false;
    v_mensaje := 'Confirmación registrada exitosamente. Comunidad: ' || v_total_restablecido || ' restablecido(s), ' || v_total_sin_servicio || ' sin servicio.';
  end if;

  -- Cálculo de duración de la interrupción en minutos
  v_inicio_calculo := coalesce(v_inicio_en, v_creado_en, now());
  v_fin_calculo := coalesce(v_restablecido_en, now());
  v_duracion_segundos := greatest(0, extract(epoch from (v_fin_calculo - v_inicio_calculo))::integer);
  v_duracion_minutos := (v_duracion_segundos / 60)::integer;

  return query
  select
    v_confirmacion_id,
    p_incidente_id,
    v_nuevo_estado,
    v_total_restablecido,
    v_total_sin_servicio,
    v_duracion_minutos,
    v_umbral_alcanzado,
    v_mensaje;
end;
$$;

revoke all on function public.registrar_confirmacion_ciudadana(uuid, public.tipo_confirmacion, double precision, double precision) from public;
grant execute on function public.registrar_confirmacion_ciudadana(uuid, public.tipo_confirmacion, double precision, double precision) to authenticated, anon;


-- 2. Consultar resumen comunitario y duración de un incidente
create or replace function public.consultar_resumen_confirmaciones(
  p_incidente_id uuid
)
returns table (
  incidente_id uuid,
  estado_incidente public.estado_incidente,
  inicio_en timestamptz,
  restablecido_en timestamptz,
  duracion_minutos integer,
  total_restablecido integer,
  total_sin_servicio integer,
  mi_confirmacion public.tipo_confirmacion
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_inicio timestamptz;
  v_fin timestamptz;
  v_segundos integer;
  v_minutos integer;
begin
  return query
  select
    i.id,
    i.estado,
    i.inicio_en,
    i.restablecido_en,
    greatest(0, (extract(epoch from (coalesce(i.restablecido_en, now()) - coalesce(i.inicio_en, i.creado_en))) / 60)::integer) as duracion_minutos,
    coalesce((select count(*)::integer from public.confirmacion_ciudadana c where c.incidente_id = i.id and c.tipo = 'restablecido'), 0) as total_restablecido,
    coalesce((select count(*)::integer from public.confirmacion_ciudadana c where c.incidente_id = i.id and c.tipo = 'sin_servicio'), 0) as total_sin_servicio,
    (select c.tipo from public.confirmacion_ciudadana c where c.incidente_id = i.id and c.ciudadano_id = auth.uid() limit 1) as mi_confirmacion
  from public.incidente i
  where i.id = p_incidente_id;
end;
$$;

revoke all on function public.consultar_resumen_confirmaciones(uuid) from public;
grant execute on function public.consultar_resumen_confirmaciones(uuid) to authenticated, anon;
