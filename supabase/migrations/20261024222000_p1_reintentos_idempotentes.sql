-- SERVI-RED | Persona 1 | Fase 4: reintentos idempotentes sin consumir cuota

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
  correlation_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_correlation_id uuid;
  v_ubicacion extensions.geography;
begin
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

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(auth.uid()::text || ':' || p_client_request_id::text, 0)
  );
  v_correlation_id := private.correlation_id_actual();

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

    return query
    select r.id, r.estado, r.creado_en, v_correlation_id
    from public.reporte r
    where r.id = v_id;
    return;
  end if;

  v_ubicacion := extensions.st_setsrid(
    extensions.st_makepoint(p_lng, p_lat), 4326
  )::extensions.geography;

  insert into public.reporte (
    client_request_id, ciudadano_id, servicio_id, municipio_codigo,
    ubicacion, descripcion, url_evidencia, inicio_estimado
  )
  values (
    p_client_request_id, auth.uid(), p_servicio_id, p_municipio_codigo,
    v_ubicacion, nullif(btrim(p_descripcion), ''), p_url_evidencia, p_inicio_estimado
  )
  on conflict (client_request_id) do nothing
  returning id into v_id;

  if v_id is null then
    select r.id into v_id
    from public.reporte r
    where r.client_request_id = p_client_request_id
      and r.ciudadano_id = auth.uid();

    if v_id is null then
      raise exception 'client_request_id ya está asociado a otra solicitud'
        using errcode = 'PT409';
    end if;
  end if;

  return query
  select r.id, r.estado, r.creado_en, v_correlation_id
  from public.reporte r
  where r.id = v_id;
end;
$$;

create or replace function public.registrar_denuncia(
  p_client_request_id uuid,
  p_servicio_id       smallint,
  p_municipio_codigo  bpchar,
  p_descripcion       text,
  p_codigo            text,
  p_lat               double precision default null,
  p_lng               double precision default null,
  p_url_evidencia     text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_ubicacion extensions.geography;
  v_seguimiento_hash text;
  v_hash_entrada text;
  v_ip inet;
begin
  if p_client_request_id is null then
    raise exception 'client_request_id es obligatorio' using errcode = 'PT400';
  end if;
  if p_codigo is null or length(btrim(p_codigo)) not between 16 and 256 then
    raise exception 'El código de seguimiento debe tener entre 16 y 256 caracteres'
      using errcode = 'PT400';
  end if;
  if p_municipio_codigo is null or p_servicio_id is null then
    raise exception 'El servicio y el municipio son obligatorios' using errcode = 'PT400';
  end if;
  if p_descripcion is null or char_length(btrim(p_descripcion)) not between 10 and 2000 then
    raise exception 'La descripción debe tener entre 10 y 2000 caracteres'
      using errcode = 'PT400';
  end if;
  if (p_lat is null) <> (p_lng is null) then
    raise exception 'Debe enviar ambas coordenadas o ninguna' using errcode = 'PT400';
  end if;
  if p_lat is not null then
    if p_lat not between -90 and 90 or p_lng not between -180 and 180 then
      raise exception 'Coordenadas fuera de rango' using errcode = 'PT400';
    end if;
    v_ubicacion := extensions.st_setsrid(
      extensions.st_makepoint(p_lng, p_lat), 4326
    )::extensions.geography;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_client_request_id::text, 1)
  );
  perform private.correlation_id_actual();
  v_hash_entrada := encode(extensions.digest(btrim(p_codigo), 'sha256'), 'hex');

  select d.id, d.seguimiento_hash into v_id, v_seguimiento_hash
  from public.denuncia d
  where d.client_request_id = p_client_request_id;

  if v_id is not null then
    if v_seguimiento_hash <> v_hash_entrada then
      raise exception 'client_request_id ya está asociado a otra solicitud'
        using errcode = 'PT409';
    end if;
    return v_id;
  end if;

  v_ip := private.ip_solicitante_actual();
  perform private.consumir_limite('denuncia', v_ip::text, 600, 3);
  perform private.consumir_limite('denuncia', v_ip::text, 86400, 10);

  insert into public.denuncia (
    client_request_id, servicio_id, municipio_codigo, ubicacion_aprox,
    descripcion, url_evidencia, seguimiento_hash
  ) values (
    p_client_request_id, p_servicio_id, p_municipio_codigo, v_ubicacion,
    btrim(p_descripcion), p_url_evidencia, v_hash_entrada
  )
  on conflict (client_request_id) do nothing
  returning id into v_id;

  if v_id is null then
    select d.id into v_id
    from public.denuncia d
    where d.client_request_id = p_client_request_id;
  end if;
  return v_id;
end;
$$;

revoke execute on function public.registrar_reporte(
  uuid, smallint, bpchar, double precision, double precision, text, text, timestamptz
) from public, anon;
grant execute on function public.registrar_reporte(
  uuid, smallint, bpchar, double precision, double precision, text, text, timestamptz
) to authenticated;

revoke execute on function public.registrar_denuncia(
  uuid, smallint, bpchar, text, text, double precision, double precision, text
) from public;
grant execute on function public.registrar_denuncia(
  uuid, smallint, bpchar, text, text, double precision, double precision, text
) to anon, authenticated;
