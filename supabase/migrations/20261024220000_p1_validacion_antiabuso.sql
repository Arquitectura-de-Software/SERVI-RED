-- SERVI-RED | Persona 1 | Fase 4: validación, correlación e idempotencia

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table private.rate_limit_secret (
  id smallint primary key check (id = 1),
  secret uuid not null
);
insert into private.rate_limit_secret (id, secret)
values (1, gen_random_uuid())
on conflict (id) do nothing;

create table private.rate_limit_bucket (
  operacion text not null,
  sujeto_hash text not null,
  ventana_segundos integer not null,
  ventana_inicio timestamptz not null,
  solicitudes integer not null check (solicitudes > 0),
  primary key (operacion, sujeto_hash, ventana_segundos, ventana_inicio)
);
create index rate_limit_bucket_expiracion_idx
  on private.rate_limit_bucket (ventana_inicio);
revoke all on private.rate_limit_secret, private.rate_limit_bucket
  from public, anon, authenticated, service_role;

alter table public.reporte
  alter column municipio_codigo set not null,
  add constraint reporte_descripcion_validacion
    check (
      descripcion is null
      or char_length(btrim(descripcion)) between 1 and 1000
    );

alter table public.denuncia
  alter column municipio_codigo set not null,
  drop constraint denuncia_descripcion_check,
  add constraint denuncia_descripcion_validacion
    check (char_length(btrim(descripcion)) between 10 and 2000);

create or replace function private.correlation_id_actual()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actual text;
  v_headers jsonb;
  v_header_id text;
  v_id uuid;
begin
  v_actual := nullif(current_setting('servi_red.correlation_id', true), '');
  if v_actual is not null then
    begin
      v_id := v_actual::uuid;
    exception when invalid_text_representation then
      raise exception 'Correlation ID interno inválido' using errcode = 'PT500';
    end;
    return v_id;
  end if;

  v_actual := current_setting('request.headers', true);
  if v_actual is not null and v_actual <> '' then
    begin
      v_headers := v_actual::jsonb;
    exception when invalid_text_representation then
      raise exception 'Encabezados de solicitud inválidos' using errcode = 'PT400';
    end;
    v_header_id := nullif(btrim(v_headers ->> 'x-correlation-id'), '');
  end if;

  if v_header_id is not null then
    begin
      v_id := v_header_id::uuid;
    exception when invalid_text_representation then
      raise exception 'El encabezado x-correlation-id debe ser un UUID'
        using errcode = 'PT400';
    end;
  else
    v_id := gen_random_uuid();
  end if;

  perform set_config('servi_red.correlation_id', v_id::text, true);
  return v_id;
end;
$$;

revoke all on function private.correlation_id_actual() from public, anon, authenticated;

create or replace function private.consumir_limite(
  p_operacion text,
  p_sujeto text,
  p_ventana_segundos integer,
  p_max_solicitudes integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash text;
  v_ventana_inicio timestamptz;
  v_secret uuid;
begin
  if p_operacion is null or p_sujeto is null
     or p_ventana_segundos < 1 or p_max_solicitudes < 1 then
    raise exception 'Configuración interna de límite inválida'
      using errcode = 'PT500';
  end if;

  select s.secret into strict v_secret
  from private.rate_limit_secret s
  where s.id = 1;

  v_hash := encode(
    extensions.digest(v_secret::text || ':' || p_sujeto, 'sha256'),
    'hex'
  );
  v_ventana_inicio := to_timestamp(
    floor(extract(epoch from now()) / p_ventana_segundos) * p_ventana_segundos
  );

  insert into private.rate_limit_bucket (
    operacion, sujeto_hash, ventana_segundos, ventana_inicio, solicitudes
  )
  values (p_operacion, v_hash, p_ventana_segundos, v_ventana_inicio, 1)
  on conflict (operacion, sujeto_hash, ventana_segundos, ventana_inicio)
  do update set solicitudes = private.rate_limit_bucket.solicitudes + 1
    where private.rate_limit_bucket.solicitudes < p_max_solicitudes;

  if not found then
    raise exception 'Se alcanzó el límite de solicitudes para %', p_operacion
      using errcode = 'PT429',
            detail = 'Espere a que se renueve la ventana de solicitudes.';
  end if;

  -- Mantiene solo un día de historial para limitar el crecimiento de la tabla.
  delete from private.rate_limit_bucket
  where ventana_inicio < now() - interval '1 day';
end;
$$;

revoke all on function private.consumir_limite(text, text, integer, integer)
  from public, anon, authenticated;

create or replace function private.ip_solicitante_actual()
returns inet
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_headers jsonb;
  v_ip text;
begin
  begin
    v_headers := nullif(current_setting('request.headers', true), '')::jsonb;
  exception when invalid_text_representation then
    raise exception 'Encabezados de solicitud inválidos' using errcode = 'PT400';
  end;

  v_ip := coalesce(
    nullif(btrim(v_headers ->> 'cf-connecting-ip'), ''),
    nullif(btrim(v_headers ->> 'x-real-ip'), ''),
    nullif(btrim(split_part(v_headers ->> 'x-forwarded-for', ',', 1)), '')
  );

  if v_ip is null then
    raise exception 'No se pudo determinar el origen de la solicitud'
      using errcode = 'PT400';
  end if;

  begin
    return v_ip::inet;
  exception when invalid_text_representation then
    raise exception 'La dirección de origen no es válida' using errcode = 'PT400';
  end;
end;
$$;

revoke all on function private.ip_solicitante_actual() from public, anon, authenticated;

create or replace function private.aplicar_limite_reporte()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
begin
  v_uid := auth.uid();
  if v_uid is not null then
    perform private.consumir_limite('reporte', v_uid::text, 60, 5);
    perform private.consumir_limite('reporte', v_uid::text, 86400, 30);
  end if;
  return new;
end;
$$;

revoke all on function private.aplicar_limite_reporte() from public, anon, authenticated;

create trigger reporte_limite_solicitudes
  before insert on public.reporte
  for each row execute function private.aplicar_limite_reporte();

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

  v_correlation_id := private.correlation_id_actual();
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

revoke all on function public.registrar_reporte(
  uuid, smallint, bpchar, double precision, double precision, text, text, timestamptz
) from public, anon;
grant execute on function public.registrar_reporte(
  uuid, smallint, bpchar, double precision, double precision, text, text, timestamptz
) to authenticated;

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

  perform private.correlation_id_actual();
  perform private.consumir_limite(
    'denuncia', private.ip_solicitante_actual()::text, 600, 3
  );
  perform private.consumir_limite(
    'denuncia', private.ip_solicitante_actual()::text, 86400, 10
  );

  insert into public.denuncia (
    client_request_id, servicio_id, municipio_codigo, ubicacion_aprox,
    descripcion, url_evidencia, seguimiento_hash
  ) values (
    p_client_request_id, p_servicio_id, p_municipio_codigo, v_ubicacion,
    btrim(p_descripcion), p_url_evidencia,
    encode(extensions.digest(btrim(p_codigo), 'sha256'), 'hex')
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

revoke execute on function public.registrar_denuncia(
  uuid, smallint, bpchar, text, text, double precision, double precision, text
) from public;
grant execute on function public.registrar_denuncia(
  uuid, smallint, bpchar, text, text, double precision, double precision, text
) to anon, authenticated;

create or replace function private.asignar_correlation_id_auditoria()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.correlation_id := coalesce(new.correlation_id, private.correlation_id_actual());
  return new;
end;
$$;
revoke all on function private.asignar_correlation_id_auditoria() from public, anon, authenticated;

create trigger audit_log_correlation_id
  before insert on public.audit_log
  for each row execute function private.asignar_correlation_id_auditoria();

create or replace function private.asignar_correlation_id_outbox()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.correlation_id := private.correlation_id_actual();
  return new;
end;
$$;
revoke all on function private.asignar_correlation_id_outbox() from public, anon, authenticated;

create trigger evento_outbox_correlation_id
  before insert on public.evento_outbox
  for each row execute function private.asignar_correlation_id_outbox();
