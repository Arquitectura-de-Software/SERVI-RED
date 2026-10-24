-- =====================================================================
-- SERVI-RED | Persona 1 | Fase 2, paso 3c: denuncias anónimas y validaciones
-- =====================================================================

-- digest() para hashear el código de seguimiento (Supabase ya lo trae activo)
create extension if not exists pgcrypto with schema extensions;

-- ---------- denuncia ----------
-- La tabla NO tiene política de INSERT: las denuncias entran solo por la función
-- registrar_denuncia(), que no exige sesión y no guarda nada que identifique al
-- denunciante (ADR-02, req. 11).
revoke insert, delete on denuncia from anon, authenticated;

-- Las lee un operador cuya empresa cubre ese servicio y municipio (y admin).
-- Ningún ciudadano puede leer denuncias, ni siquiera las suyas.
create policy denuncia_select on denuncia for select to authenticated
using (
  (select public.rol_actual()) = 'admin'
  or public.operador_cubre(servicio_id, municipio_codigo)
);

create policy denuncia_update on denuncia for update to authenticated
using (
  (select public.rol_actual()) = 'admin'
  or public.operador_cubre(servicio_id, municipio_codigo)
)
with check (
  (select public.rol_actual()) = 'admin'
  or public.operador_cubre(servicio_id, municipio_codigo)
);

revoke update on denuncia from anon, authenticated;
grant update (estado) on denuncia to authenticated;

-- Registrar una denuncia anónima.
-- El cliente genera un código de seguimiento aleatorio (mínimo 16 caracteres), lo
-- guarda en el dispositivo y lo envía aquí; el servidor guarda solo su hash.
-- Reintentar con el mismo client_request_id es seguro (idempotente).
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
  if p_codigo is null or length(p_codigo) < 16 then
    raise exception 'El código de seguimiento debe tener al menos 16 caracteres'
      using errcode = '22023';
  end if;
  if p_municipio_codigo is null then
    raise exception 'El municipio es obligatorio'
      using errcode = '22023';
  end if;
  if p_lat is not null and p_lng is not null then
    if p_lat not between -90 and 90 or p_lng not between -180 and 180 then
      raise exception 'Coordenadas fuera de rango' using errcode = '22023';
    end if;
    v_ubicacion := extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography;
  end if;

  insert into public.denuncia (
    client_request_id, servicio_id, municipio_codigo, ubicacion_aprox,
    descripcion, url_evidencia, seguimiento_hash
  ) values (
    p_client_request_id, p_servicio_id, p_municipio_codigo, v_ubicacion,
    p_descripcion, p_url_evidencia,
    encode(extensions.digest(p_codigo, 'sha256'), 'hex')
  )
  on conflict (client_request_id) do nothing
  returning id into v_id;

  if v_id is null then
    select d.id into v_id from public.denuncia d
    where d.client_request_id = p_client_request_id;
  end if;
  return v_id;
end;
$$;

-- Consultar el estado de una denuncia con el código de seguimiento.
create or replace function public.consultar_denuncia(p_codigo text)
returns table (estado public.estado_denuncia, creada_en timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select d.estado, d.creada_en
  from public.denuncia d
  where length(p_codigo) >= 16
    and d.seguimiento_hash = encode(extensions.digest(p_codigo, 'sha256'), 'hex')
$$;

revoke execute on function public.registrar_denuncia(uuid, smallint, bpchar, text, text, double precision, double precision, text) from public;
revoke execute on function public.consultar_denuncia(text) from public;
grant execute on function public.registrar_denuncia(uuid, smallint, bpchar, text, text, double precision, double precision, text) to anon, authenticated;
grant execute on function public.consultar_denuncia(text) to anon, authenticated;

-- ---------- validacion (moderación) ----------
-- Un operador valida reportes o denuncias que cubre (la comprobación de cobertura
-- sale de las políticas de reporte y denuncia).
create policy validacion_select on validacion for select to authenticated
using (
  operador_id = (select auth.uid())
  or (select public.rol_actual()) = 'admin'
  or exists (
    select 1 from operador o
    where o.id = validacion.operador_id
      and o.empresa_id = (select public.empresa_actual())
  )
);

create policy validacion_insert on validacion for insert to authenticated
with check (
  (select public.rol_actual()) = 'operador'
  and operador_id = (select auth.uid())
  and (
    reporte_id in (select id from reporte)
    or denuncia_id in (select id from denuncia)
  )
);

create policy validacion_update on validacion for update to authenticated
using (operador_id = (select auth.uid()))
with check (operador_id = (select auth.uid()));

revoke update on validacion from anon, authenticated;
grant update (estado, comentario) on validacion to authenticated;