-- =====================================================================
-- SERVI-RED | Persona 4 | Tiempo real para el portal del operador
-- =====================================================================
-- Se usa Realtime Broadcast desde la base (realtime.send) en canales PRIVADOS,
-- en vez de agregar tablas a la publicación supabase_realtime:
--   * el mensaje lleva solo lo necesario para refrescar (ids, estado,
--     prioridad), nunca descripciones, ciudadano_id, hash ni coordenadas;
--   * no hace falta replica identity full en reporte/denuncia;
--   * denuncia no entra en supabase_realtime.
--
-- Canales (topic):
--   empresa:<uuid>  operadores activos de esa empresa
--   admin           administradores (todos los incidentes, incluidos los sin empresa)
-- Eventos:
--   incidente_cambiado  {id, estado, prioridad, empresa_id, operador_asignado, servicio_id, municipio_codigo}
--   cola_cambiada       {tipo, id}   (denuncia/reporte nuevo o moderado)
-- El portal se suscribe con supabase.channel('empresa:<id>', {config: {private: true}})
-- y, al recibir un evento, vuelve a consultar la vista correspondiente (que
-- aplica la RLS). La política sobre realtime.messages es esquema de Supabase:
-- se coordina con P1 y con P3 (la app móvil también usa Realtime).
-- realtime.send captura sus propios errores (solo emite un WARNING), así que un
-- fallo de Realtime nunca deshace la operación de negocio.

-- ---------- 1. a qué canales va un mensaje ----------
create or replace function private.p4_topics_cobertura(p_servicio_id smallint, p_municipio bpchar)
returns setof text
language sql
stable
security definer
set search_path = ''
as $$
  select distinct 'empresa:' || c.empresa_id::text
  from public.empresa_cobertura c
  where c.servicio_id = p_servicio_id and c.municipio_codigo = p_municipio
  union
  select 'admin'
$$;
revoke all on function private.p4_topics_cobertura(smallint, bpchar) from public, anon, authenticated;

-- ---------- 2. incidente creado o modificado ----------
create or replace function private.p4_broadcast_incidente()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payload jsonb;
begin
  if to_regprocedure('realtime.send(jsonb,text,text,boolean)') is null then
    return null;
  end if;

  v_payload := jsonb_build_object(
    'id', new.id,
    'estado', new.estado,
    'prioridad', new.prioridad,
    'empresa_id', new.empresa_id,
    'operador_asignado', new.operador_asignado,
    'servicio_id', new.servicio_id,
    'municipio_codigo', new.municipio_codigo,
    'operacion', lower(tg_op));

  if new.empresa_id is not null then
    perform realtime.send(v_payload, 'incidente_cambiado', 'empresa:' || new.empresa_id::text, true);
  end if;
  -- Si cambió de empresa, la anterior también debe refrescar (el incidente sale de su mapa).
  if tg_op = 'UPDATE' and old.empresa_id is not null and old.empresa_id is distinct from new.empresa_id then
    perform realtime.send(v_payload, 'incidente_cambiado', 'empresa:' || old.empresa_id::text, true);
  end if;
  perform realtime.send(v_payload, 'incidente_cambiado', 'admin', true);
  return null;
end;
$$;
revoke all on function private.p4_broadcast_incidente() from public, anon, authenticated;

drop trigger if exists p4_broadcast_incidente on public.incidente;
create trigger p4_broadcast_incidente
  after insert or update on public.incidente
  for each row execute function private.p4_broadcast_incidente();

-- ---------- 3. cola de moderación ----------
-- Denuncia o reporte nuevo: avisa a las empresas que cubren servicio y municipio.
-- Validación nueva: avisa igual (el elemento sale de la cola de todos).
-- Solo {tipo, id}: el portal relee cola_moderacion con su RLS.
create or replace function private.p4_broadcast_cola()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tipo      text;
  v_id        uuid;
  v_servicio  smallint;
  v_municipio bpchar;
  v_topic     text;
begin
  if to_regprocedure('realtime.send(jsonb,text,text,boolean)') is null then
    return null;
  end if;

  if tg_table_name = 'validacion' then
    if new.denuncia_id is not null then
      v_tipo := 'denuncia'; v_id := new.denuncia_id;
      select d.servicio_id, d.municipio_codigo into v_servicio, v_municipio
      from public.denuncia d where d.id = new.denuncia_id;
    else
      v_tipo := 'reporte'; v_id := new.reporte_id;
      select r.servicio_id, r.municipio_codigo into v_servicio, v_municipio
      from public.reporte r where r.id = new.reporte_id;
    end if;
  else
    v_tipo := tg_table_name; v_id := new.id;
    v_servicio := new.servicio_id; v_municipio := new.municipio_codigo;
  end if;

  if v_servicio is null then
    return null;
  end if;

  for v_topic in select t from private.p4_topics_cobertura(v_servicio, v_municipio) t loop
    perform realtime.send(jsonb_build_object('tipo', v_tipo, 'id', v_id), 'cola_cambiada', v_topic, true);
  end loop;
  return null;
end;
$$;
revoke all on function private.p4_broadcast_cola() from public, anon, authenticated;

drop trigger if exists p4_broadcast_cola on public.denuncia;
create trigger p4_broadcast_cola
  after insert on public.denuncia
  for each row execute function private.p4_broadcast_cola();

drop trigger if exists p4_broadcast_cola on public.reporte;
create trigger p4_broadcast_cola
  after insert on public.reporte
  for each row execute function private.p4_broadcast_cola();

drop trigger if exists p4_broadcast_cola on public.validacion;
create trigger p4_broadcast_cola
  after insert on public.validacion
  for each row execute function private.p4_broadcast_cola();

-- ---------- 4. quién puede escuchar cada canal ----------
-- Solo lectura (select): los clientes no pueden publicar en estos canales.
-- Se crea solo si el esquema de Realtime existe (idempotente).
do $$
begin
  if to_regclass('realtime.messages') is null then
    raise notice 'realtime.messages no existe: no se crea la política de canales P4.';
    return;
  end if;

  drop policy if exists p4_canales_operacion on realtime.messages;
  create policy p4_canales_operacion on realtime.messages
    for select to authenticated
    using (
      realtime.messages.extension = 'broadcast'
      and (
        (realtime.topic() = 'empresa:' || (select public.empresa_actual())::text
           and (select public.rol_actual()) = 'operador')
        or (realtime.topic() = 'admin' and (select public.rol_actual()) = 'admin')
      )
    );
end $$;
