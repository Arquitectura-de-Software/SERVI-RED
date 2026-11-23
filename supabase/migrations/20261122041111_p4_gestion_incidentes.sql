-- =====================================================================
-- SERVI-RED | Persona 4 | Gestión de incidentes desde el portal del operador
-- =====================================================================
-- RPC para el portal: cambiar estado (con mensaje opcional), asignar operador,
-- asignar empresa (admin) y responder; y una vista con lat/lng para el mapa.
--
-- Reglas que se reutilizan de la Persona 1 (no se duplican):
--   * transiciones válidas: tabla transicion_incidente + trigger de estados
--   * quién gestiona un incidente: RLS incidente_update
--   * quién responde: RLS respuesta_insert
--   * auditoría (req. 19) y outbox: triggers existentes
--
-- Códigos de error (PostgREST los traduce a HTTP):
--   42501 -> 403 sin permiso | PT404 -> 404 no existe | PT400 -> 400 datos inválidos
--   PT409 -> 409 transición no permitida o conflicto

-- ---------- 1. cambiar estado ----------
-- Se ejecuta con los permisos de quien llama: la RLS de P1 decide si puede gestionarlo.
create or replace function public.cambiar_estado_incidente(
  p_incidente_id uuid,
  p_estado       public.estado_incidente,
  p_mensaje      text default null
)
returns table (
  incidente_id     uuid,
  estado           public.estado_incidente,
  restablecido_en  timestamptz,
  cerrado_en       timestamptz,
  actualizado_en   timestamptz,
  respuesta_id     uuid
)
language plpgsql
security invoker
-- 'public' y no '': el trigger de estados de P1 (validar_transicion_incidente)
-- no fija su search_path y busca transicion_incidente sin esquema.
set search_path = public
as $$
declare
  v_actual     public.estado_incidente;
  v_respuesta  uuid;
  v_permitidos text;
begin
  if public.rol_actual() is distinct from 'operador' and public.rol_actual() is distinct from 'admin' then
    raise exception 'Solo un operador o un administrador gestiona incidentes' using errcode = '42501';
  end if;
  if p_incidente_id is null or p_estado is null then
    raise exception 'El incidente y el estado son obligatorios' using errcode = 'PT400';
  end if;
  if p_mensaje is not null and char_length(btrim(p_mensaje)) not between 1 and 2000 then
    raise exception 'El mensaje debe tener entre 1 y 2000 caracteres' using errcode = 'PT400';
  end if;

  if not exists (select 1 from public.incidente i where i.id = p_incidente_id) then
    raise exception 'El incidente no existe' using errcode = 'PT404';
  end if;

  -- FOR UPDATE aplica también la política de UPDATE: si no lo gestiona, no hay fila.
  select i.estado into v_actual
  from public.incidente i
  where i.id = p_incidente_id
  for update;

  if not found then
    raise exception 'No gestiona este incidente' using errcode = '42501';
  end if;

  if v_actual <> p_estado then
    if not exists (select 1 from public.transicion_incidente t
                   where t.desde = v_actual and t.hacia = p_estado) then
      select string_agg(t.hacia::text, ', ' order by t.hacia) into v_permitidos
      from public.transicion_incidente t where t.desde = v_actual;
      raise exception 'Transición no permitida: % -> %', v_actual, p_estado
        using errcode = 'PT409',
              hint = 'Desde ' || v_actual || ' se puede pasar a: ' || coalesce(v_permitidos, '(ninguno)');
    end if;

    update public.incidente i set estado = p_estado where i.id = p_incidente_id;
  end if;
  -- Si ya estaba en ese estado no se cambia nada (reintento idempotente),
  -- pero el mensaje, si viene, sí se registra.

  if p_mensaje is not null then
    insert into public.respuesta (incidente_id, operador_id, mensaje)
    values (p_incidente_id, auth.uid(), btrim(p_mensaje))
    returning id into v_respuesta;
  end if;

  return query
  select i.id, i.estado, i.restablecido_en, i.cerrado_en, i.actualizado_en, v_respuesta
  from public.incidente i where i.id = p_incidente_id;
end;
$$;

revoke all on function public.cambiar_estado_incidente(uuid, public.estado_incidente, text) from public, anon;
grant execute on function public.cambiar_estado_incidente(uuid, public.estado_incidente, text) to authenticated;

-- ---------- 2. asignar operador ----------
-- security definer porque necesita saber si el operador destino está activo
-- (perfil solo lo lee su dueño o el admin). Repite las condiciones de la RLS
-- incidente_update y además exige operador activo de la empresa del incidente.
create or replace function public.asignar_incidente(
  p_incidente_id uuid,
  p_operador_id  uuid      -- null = quitar la asignación
)
returns table (incidente_id uuid, operador_asignado uuid, actualizado_en timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rol      public.rol_usuario := public.rol_actual();
  v_inc      public.incidente%rowtype;
begin
  if v_rol is distinct from 'operador' and v_rol is distinct from 'admin' then
    raise exception 'Solo un operador o un administrador asigna incidentes' using errcode = '42501';
  end if;
  if p_incidente_id is null then
    raise exception 'El incidente es obligatorio' using errcode = 'PT400';
  end if;

  select * into v_inc from public.incidente i where i.id = p_incidente_id for update;
  if not found then
    raise exception 'El incidente no existe' using errcode = 'PT404';
  end if;

  if v_rol = 'operador' and not (
       v_inc.empresa_id = public.empresa_actual()
       and public.operador_cubre(v_inc.servicio_id, v_inc.municipio_codigo)) then
    raise exception 'No gestiona este incidente' using errcode = '42501';
  end if;

  if v_inc.estado = 'cerrado' then
    raise exception 'Un incidente cerrado no se reasigna' using errcode = 'PT409';
  end if;

  if p_operador_id is not null then
    if v_inc.empresa_id is null then
      raise exception 'El incidente no tiene empresa; un administrador debe asignarla primero'
        using errcode = 'PT409';
    end if;
    if not exists (
      select 1 from public.operador o
      join public.perfil p on p.id = o.id
      where o.id = p_operador_id
        and o.empresa_id = v_inc.empresa_id
        and p.rol = 'operador'
        and p.activo
    ) then
      raise exception 'El operador no existe, está inactivo o es de otra empresa' using errcode = 'PT400';
    end if;
  end if;

  update public.incidente i set operador_asignado = p_operador_id where i.id = p_incidente_id;

  return query
  select i.id, i.operador_asignado, i.actualizado_en from public.incidente i where i.id = p_incidente_id;
end;
$$;

revoke all on function public.asignar_incidente(uuid, uuid) from public, anon;
grant execute on function public.asignar_incidente(uuid, uuid) to authenticated;

-- ---------- 3. asignar empresa (solo admin) ----------
-- Para incidentes que la agrupación dejó sin empresa (cobertura ambigua o
-- inexistente). empresa_id no está entre las columnas editables por el cliente.
create or replace function public.asignar_empresa_incidente(
  p_incidente_id uuid,
  p_empresa_id   uuid
)
returns table (incidente_id uuid, empresa_id uuid, actualizado_en timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inc public.incidente%rowtype;
begin
  if public.rol_actual() is distinct from 'admin' then
    raise exception 'Solo un administrador asigna la empresa de un incidente' using errcode = '42501';
  end if;

  select * into v_inc from public.incidente i where i.id = p_incidente_id for update;
  if not found then
    raise exception 'El incidente no existe' using errcode = 'PT404';
  end if;
  if v_inc.estado = 'cerrado' then
    raise exception 'Un incidente cerrado no cambia de empresa' using errcode = 'PT409';
  end if;
  if not exists (
    select 1 from public.empresa_cobertura c
    where c.empresa_id = p_empresa_id
      and c.servicio_id = v_inc.servicio_id
      and c.municipio_codigo = v_inc.municipio_codigo
  ) then
    raise exception 'La empresa no presta ese servicio en ese municipio' using errcode = 'PT400';
  end if;

  -- Al cambiar de empresa, el operador asignado (de la empresa anterior) deja de valer.
  update public.incidente i
     set empresa_id = p_empresa_id,
         operador_asignado = case when v_inc.empresa_id is distinct from p_empresa_id
                                  then null else i.operador_asignado end
   where i.id = p_incidente_id;

  return query
  select i.id, i.empresa_id, i.actualizado_en from public.incidente i where i.id = p_incidente_id;
end;
$$;

revoke all on function public.asignar_empresa_incidente(uuid, uuid) from public, anon;
grant execute on function public.asignar_empresa_incidente(uuid, uuid) to authenticated;

-- ---------- 4. responder ----------
-- Con los permisos de quien llama: la RLS respuesta_insert de P1 decide.
create or replace function public.responder(
  p_mensaje      text,
  p_incidente_id uuid default null,
  p_reporte_id   uuid default null
)
returns table (respuesta_id uuid, respondida_en timestamptz)
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if public.rol_actual() is distinct from 'operador' then
    raise exception 'Solo un operador responde' using errcode = '42501';
  end if;
  if p_incidente_id is null and p_reporte_id is null then
    raise exception 'Indique el incidente o el reporte que responde' using errcode = 'PT400';
  end if;
  if p_mensaje is null or char_length(btrim(p_mensaje)) not between 1 and 2000 then
    raise exception 'El mensaje debe tener entre 1 y 2000 caracteres' using errcode = 'PT400';
  end if;
  if p_reporte_id is not null and p_incidente_id is not null and not exists (
    select 1 from public.reporte r where r.id = p_reporte_id and r.incidente_id = p_incidente_id
  ) then
    raise exception 'El reporte no pertenece a ese incidente' using errcode = 'PT400';
  end if;

  return query
  insert into public.respuesta (incidente_id, reporte_id, operador_id, mensaje)
  values (p_incidente_id, p_reporte_id, auth.uid(), btrim(p_mensaje))
  returning respuesta.id, respuesta.fecha_resp;
end;
$$;

revoke all on function public.responder(text, uuid, uuid) from public, anon;
grant execute on function public.responder(text, uuid, uuid) to authenticated;

-- ---------- 5. vista para el mapa y la lista ----------
-- security_invoker: cada quien ve lo que su RLS le permite. Los conteos de
-- reportes y el nombre del operador asignado se calculan con esos permisos
-- (un ciudadano ve los incidentes pero no los reportes ni los operadores ajenos).
create or replace view public.incidente_operacion
with (security_invoker = true)
as
select
  i.id,
  i.servicio_id,
  s.tipo                    as servicio_tipo,
  s.descripcion             as servicio,
  i.empresa_id,
  e.nombre                  as empresa,
  i.municipio_codigo,
  m.nombre                  as municipio,
  m.departamento_codigo,
  i.estado,
  i.prioridad,
  extensions.st_y(i.centroide::extensions.geometry) as lat,
  extensions.st_x(i.centroide::extensions.geometry) as lng,
  i.operador_asignado,
  o.nombre_completo         as operador_asignado_nombre,
  i.inicio_en,
  i.restablecido_en,
  i.cerrado_en,
  i.creado_en,
  i.actualizado_en,
  rs.total_reportes,
  rs.ultimo_reporte_en
from public.incidente i
join public.servicio s       on s.id = i.servicio_id
left join public.empresa e   on e.id = i.empresa_id
left join public.municipio m on m.codigo_dane = i.municipio_codigo
left join public.operador o  on o.id = i.operador_asignado
left join lateral (
  select count(*)::int as total_reportes, max(r.creado_en) as ultimo_reporte_en
  from public.reporte r
  where r.incidente_id = i.id
) rs on true;

comment on view public.incidente_operacion is
  'P4: incidentes con lat/lng y datos de catálogo para el portal del operador. Respeta la RLS de quien consulta.';

revoke all on public.incidente_operacion from public, anon;
grant select on public.incidente_operacion to authenticated;
