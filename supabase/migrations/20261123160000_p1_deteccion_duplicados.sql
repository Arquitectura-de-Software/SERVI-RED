-- SERVI-RED | Persona 1 | Punto 5: Detección de duplicados con ST_DWithin
-- Reemplaza public.registrar_reporte extendiendo el retorno con:
--   es_duplicado boolean          → true si el ciudadano ya reportó lo mismo en 500m/4h
--   incidente_cercano_id uuid     → UUID del incidente al que se vinculó el nuevo reporte
--   incidente_cercano_distancia double precision → metros de distancia al incidente cercano
--
-- NOTA: nunca se edita la migración anterior; se usa CREATE OR REPLACE para sobrescribir
--       en la base de datos conservando los permisos heredados del GRANT al final.

create or replace function public.registrar_reporte(
  p_client_request_id uuid,
  p_servicio_id smallint,
  p_municipio_codigo bpchar,
  p_lat double precision,
  p_lng double precision,
  p_descripcion text default null,
  p_url_evidencia text default null,
  p_inicio_estimado timestamptz default null
)
returns table (
  reporte_id uuid,
  estado public.estado_reporte,
  creado_en timestamptz,
  correlation_id uuid,
  es_duplicado boolean,
  incidente_cercano_id uuid,
  incidente_cercano_distancia double precision
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_correlation_id uuid;
  v_ubicacion extensions.geography;
  v_duplicado_id uuid;
  v_duplicado_estado public.estado_reporte;
  v_incidente_id uuid;
  v_incidente_distancia double precision;
begin
  -- ── 1. Validaciones de sesión y parámetros ──────────────────────────────────
  if auth.uid() is null or public.rol_actual() is distinct from 'ciudadano' then
    raise exception 'Se requiere una sesión ciudadana activa' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'client_request_id es obligatorio' using errcode = 'PT400';
  end if;
  if p_servicio_id is null or p_municipio_codigo is null then
    raise exception 'El servicio y el municipio son obligatorios' using errcode = 'PT400';
  end if;
  if p_lat is null or p_lng is null
     or p_lat not between -90 and 90
     or p_lng not between -180 and 180 then
    raise exception 'Las coordenadas son obligatorias y deben estar dentro de rango'
      using errcode = 'PT400';
  end if;
  if p_descripcion is not null
     and char_length(btrim(p_descripcion)) not between 1 and 1000 then
    raise exception 'La descripción debe tener entre 1 y 1000 caracteres'
      using errcode = 'PT400';
  end if;

  -- ── 2. Advisory lock (idempotencia por client_request_id) ──────────────────
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(auth.uid()::text || ':' || p_client_request_id::text, 0)
  );
  v_correlation_id := private.correlation_id_actual();

  -- ── 3. Idempotencia: mismo client_request_id ya existe ──────────────────────
  select r.id into v_id
  from public.reporte r
  where r.client_request_id = p_client_request_id;

  if v_id is not null then
    if not exists (
      select 1 from public.reporte r
      where r.id = v_id and r.ciudadano_id = auth.uid()
    ) then
      raise exception 'client_request_id ya está asociado a otra solicitud'
        using errcode = 'PT409';
    end if;

    -- Retornar el existente: sin duplicado geográfico (ya fue registrado antes)
    return query
    select r.id,
           r.estado,
           r.creado_en,
           v_correlation_id,
           false::boolean,
           null::uuid,
           null::double precision
    from public.reporte r
    where r.id = v_id;
    return;
  end if;

  -- ── 4. Construir punto geográfico ───────────────────────────────────────────
  v_ubicacion := extensions.st_setsrid(
    extensions.st_makepoint(p_lng, p_lat), 4326
  )::extensions.geography;

  -- ── 5. Detección de duplicado del mismo ciudadano (500m, mismo servicio, 4h) ─
  -- Si el ciudadano ya reportó el mismo servicio a menos de 500 m en las últimas
  -- 4 horas (con un client_request_id diferente), no insertamos: devolvemos el
  -- reporte existente con es_duplicado = true.
  select r.id, r.estado
  into v_duplicado_id, v_duplicado_estado
  from public.reporte r
  where r.ciudadano_id = auth.uid()
    and r.servicio_id = p_servicio_id
    and r.client_request_id <> p_client_request_id
    and extensions.st_dwithin(r.ubicacion, v_ubicacion, 500.0)
    and r.creado_en > now() - interval '4 hours'
  order by extensions.st_distance(r.ubicacion, v_ubicacion) asc
  limit 1;

  if v_duplicado_id is not null then
    return query
    select r.id,
           r.estado,
           r.creado_en,
           v_correlation_id,
           true::boolean,
           null::uuid,
           null::double precision
    from public.reporte r
    where r.id = v_duplicado_id;
    return;
  end if;

  -- ── 6. Buscar incidente abierto cercano (500m, mismo servicio) ──────────────
  -- Si hay un incidente en estado 'recibido' o 'en_atencion' dentro de 500 m
  -- para el mismo servicio, el nuevo reporte se vincula automáticamente a él.
  select i.id,
         extensions.st_distance(i.centroide, v_ubicacion)
  into v_incidente_id, v_incidente_distancia
  from public.incidente i
  where i.servicio_id = p_servicio_id
    and i.estado in ('recibido', 'en_atencion')
    and i.centroide is not null
    and extensions.st_dwithin(i.centroide, v_ubicacion, 500.0)
  order by extensions.st_distance(i.centroide, v_ubicacion) asc
  limit 1;

  -- ── 7. Insertar el nuevo reporte ────────────────────────────────────────────
  insert into public.reporte (
    client_request_id, ciudadano_id, servicio_id, municipio_codigo,
    ubicacion, descripcion, url_evidencia, inicio_estimado, incidente_id
  )
  values (
    p_client_request_id, auth.uid(), p_servicio_id, p_municipio_codigo,
    v_ubicacion, nullif(btrim(p_descripcion), ''), p_url_evidencia,
    p_inicio_estimado,
    v_incidente_id   -- null si no hay incidente cercano
  )
  on conflict (client_request_id) do nothing
  returning id into v_id;

  if v_id is null then
    -- Colisión de concurrencia resuelta por CONFLICT: recuperar el existente
    select r.id into v_id
    from public.reporte r
    where r.client_request_id = p_client_request_id
      and r.ciudadano_id = auth.uid();

    if v_id is null then
      raise exception 'client_request_id ya está asociado a otra solicitud'
        using errcode = 'PT409';
    end if;
  end if;

  -- ── 8. Retornar con metadatos de duplicado/incidente ────────────────────────
  return query
  select r.id,
         r.estado,
         r.creado_en,
         v_correlation_id,
         false::boolean,
         v_incidente_id,
         v_incidente_distancia
  from public.reporte r
  where r.id = v_id;
end;
$$;

-- ── Permisos: idénticos a la versión anterior ──────────────────────────────────
revoke execute on function public.registrar_reporte(
  uuid, smallint, bpchar, double precision, double precision, text, text, timestamptz
) from public, anon;

grant execute on function public.registrar_reporte(
  uuid, smallint, bpchar, double precision, double precision, text, text, timestamptz
) to authenticated;
