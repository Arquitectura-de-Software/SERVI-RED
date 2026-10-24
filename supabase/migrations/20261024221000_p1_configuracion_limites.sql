-- SERVI-RED | Persona 1 | Fase 4: configuración de cuotas y origen confiable

create table private.rate_limit_policy (
  operacion text not null,
  ventana_segundos integer not null check (ventana_segundos > 0),
  max_solicitudes integer not null check (max_solicitudes > 0),
  primary key (operacion, ventana_segundos)
);

insert into private.rate_limit_policy (operacion, ventana_segundos, max_solicitudes)
values
  ('reporte', 60, 5),
  ('reporte', 86400, 30),
  ('denuncia', 600, 3),
  ('denuncia', 86400, 10);

revoke all on private.rate_limit_policy from public, anon, authenticated, service_role;

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
  v_max_solicitudes integer;
begin
  if p_operacion is null or p_sujeto is null
     or p_ventana_segundos < 1 or p_max_solicitudes < 1 then
    raise exception 'Configuración interna de límite inválida'
      using errcode = 'PT500';
  end if;

  select p.max_solicitudes into v_max_solicitudes
  from private.rate_limit_policy p
  where p.operacion = p_operacion
    and p.ventana_segundos = p_ventana_segundos;

  if not found then
    v_max_solicitudes := p_max_solicitudes;
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
    where private.rate_limit_bucket.solicitudes < v_max_solicitudes;

  if not found then
    raise exception 'Se alcanzó el límite de solicitudes para %', p_operacion
      using errcode = 'PT429',
            detail = 'Espere a que se renueve la ventana de solicitudes.';
  end if;

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
  v_forwarded_for text;
begin
  begin
    v_headers := nullif(current_setting('request.headers', true), '')::jsonb;
  exception when invalid_text_representation then
    raise exception 'Encabezados de solicitud inválidos' using errcode = 'PT400';
  end;

  v_forwarded_for := v_headers ->> 'x-forwarded-for';
  v_ip := coalesce(
    nullif(btrim(v_headers ->> 'cf-connecting-ip'), ''),
    nullif(btrim(reverse(split_part(reverse(v_forwarded_for), ',', 1))), '')
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
