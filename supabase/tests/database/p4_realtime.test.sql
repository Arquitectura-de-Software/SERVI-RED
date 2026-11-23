-- SERVI-RED | Persona 4 | Pruebas de tiempo real (Broadcast en canales privados)
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- ---------- ayudantes ----------
create function public.p4r_como(p_uid uuid) returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.headers', '{"x-forwarded-for":"192.0.2.49"}', true);
  set local role authenticated;
end $$;
create function public.p4r_serv(p text) returns smallint language sql as $$
  select id from public.servicio where tipo = p::public.tipo_servicio $$;
create function public.p4r_punto(p_norte_m double precision) returns extensions.geography language sql as $$
  select extensions.st_setsrid(extensions.st_makepoint(-74.07, 4.65 + p_norte_m / 111320.0), 4326)::extensions.geography $$;
create function public.p4r_inc(p_reporte uuid) returns uuid language sql security definer set search_path = '' as $$
  select incidente_id from public.reporte where id = p_reporte $$;
-- Mensajes de esta prueba (como postgres, sin RLS).
create function public.p4r_msgs(p_topic text, p_event text) returns integer language sql security definer set search_path = '' as $$
  select count(*)::int from realtime.messages m
  where m.topic = p_topic and m.event = p_event and m.private
    and m.inserted_at >= (now() at time zone 'utc') - interval '1 minute' $$;
create function public.p4r_emp(p_nit text) returns text language sql as $$
  select 'empresa:' || id::text from public.empresa where nit = p_nit $$;
-- Lo que ve un usuario autenticado en un canal (así autoriza Realtime: fija
-- realtime.topic y consulta realtime.messages con la RLS de quien se suscribe).
create function public.p4r_puede_leer(p_topic text) returns boolean language plpgsql as $$
declare v int;
begin
  perform set_config('realtime.topic', p_topic, true);
  select count(*) into v from realtime.messages m where m.topic = p_topic;
  return v > 0;
end $$;

-- ---------- datos ----------
-- A1: operador de energía (DEMO-0001). B1: operador de acueducto (DEMO-0002). C1: ciudadano. D1: admin.
insert into auth.users (id) values
  ('a9999999-0000-0000-0000-000000000001'), ('b9999999-0000-0000-0000-000000000001'),
  ('c9999999-0000-0000-0000-000000000001'), ('d9999999-0000-0000-0000-000000000001');
select public.promover_usuario('a9999999-0000-0000-0000-000000000001'::uuid, 'operador', (select id from empresa where nit = 'DEMO-0001'), 'Ana Realtime', 'Analista');
select public.promover_usuario('b9999999-0000-0000-0000-000000000001'::uuid, 'operador', (select id from empresa where nit = 'DEMO-0002'), 'Beatriz Realtime', 'Analista');
select public.promover_usuario('d9999999-0000-0000-0000-000000000001'::uuid, 'admin');

select ok(not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
                      and tablename in ('reporte', 'denuncia')),
  'ni reporte ni denuncia están en la publicación supabase_realtime');

-- ---------- 1. reporte nuevo -> cola_cambiada a la empresa que cubre ----------
insert into reporte (id, client_request_id, ciudadano_id, servicio_id, municipio_codigo, ubicacion, descripcion) values
  ('19000000-0000-0000-0000-000000000001', gen_random_uuid(), 'c9999999-0000-0000-0000-000000000001',
   public.p4r_serv('energia'), '11001', public.p4r_punto(0), 'Soy Juan, vivo en la calle 10');
select is(public.p4r_msgs(public.p4r_emp('DEMO-0001'), 'cola_cambiada'), 1, 'un reporte nuevo avisa a la empresa que cubre');
select is(public.p4r_msgs(public.p4r_emp('DEMO-0002'), 'cola_cambiada'), 0, 'y no a una empresa que no cubre ese servicio');
select is(public.p4r_msgs('admin', 'cola_cambiada'), 1, 'el admin también recibe el aviso');
select is((select payload - 'id' from realtime.messages where topic = public.p4r_emp('DEMO-0001') and event = 'cola_cambiada'
           order by inserted_at desc limit 1),
  jsonb_build_object('tipo', 'reporte'), 'el aviso de la cola solo lleva tipo e id');

-- ---------- 2. agrupación -> incidente_cambiado ----------
select private.agrupar_pendientes();
select set_config('p4r.ie', public.p4r_inc('19000000-0000-0000-0000-000000000001')::text, true);
select is(public.p4r_msgs(public.p4r_emp('DEMO-0001'), 'incidente_cambiado') >= 1, true,
  'el incidente nuevo se avisa a su empresa');
select is((select payload ->> 'id' from realtime.messages where topic = public.p4r_emp('DEMO-0001')
           and event = 'incidente_cambiado' order by inserted_at limit 1), current_setting('p4r.ie'),
  'el aviso lleva el id del incidente');
select is((select count(*)::int from realtime.messages where event = 'incidente_cambiado'
           and (payload ? 'centroide' or payload ? 'descripcion' or payload ? 'ciudadano_id')), 0,
  'el aviso del incidente no lleva ubicación ni datos del ciudadano');
select is(public.p4r_msgs(public.p4r_emp('DEMO-0002'), 'incidente_cambiado'), 0, 'otra empresa no recibe el aviso');

-- Cambio de estado por el operador.
select public.p4r_como('a9999999-0000-0000-0000-000000000001');
select * from public.cambiar_estado_incidente(current_setting('p4r.ie')::uuid, 'en_atencion');
reset role;
select ok(exists (select 1 from realtime.messages where topic = public.p4r_emp('DEMO-0001')
                  and event = 'incidente_cambiado' and payload ->> 'estado' = 'en_atencion'),
  'el cambio de estado se avisa con el estado nuevo');

-- ---------- 3. denuncia nueva: sin descripción ni hash ----------
insert into denuncia (id, client_request_id, servicio_id, municipio_codigo, descripcion, seguimiento_hash) values
  ('19000000-0000-0000-0000-0000000000d1', gen_random_uuid(), public.p4r_serv('energia'), '11001',
   'Conexión ilegal en el poste de la esquina', 'hash-p4-realtime');
select is((select payload - 'id' from realtime.messages where topic = public.p4r_emp('DEMO-0001') and event = 'cola_cambiada'
           and payload ->> 'id' = '19000000-0000-0000-0000-0000000000d1'),
  jsonb_build_object('tipo', 'denuncia'), 'la denuncia nueva se avisa solo con tipo e id');
select is((select count(*)::int from realtime.messages where payload::text like '%hash-p4-realtime%'
           or payload::text like '%Conexión ilegal%' or payload::text like '%calle 10%'), 0,
  'ningún mensaje lleva hash ni descripciones');

-- Moderación: también refresca la cola.
select public.p4r_como('a9999999-0000-0000-0000-000000000001');
select * from public.moderar_denuncia('19000000-0000-0000-0000-0000000000d1', 'aprobada', 'Confirmado');
reset role;
select is(public.p4r_msgs(public.p4r_emp('DEMO-0001'), 'cola_cambiada'), 3,
  'la moderación avisa a la empresa (reporte + denuncia + validación)');

-- ---------- 4. autorización de los canales (RLS de realtime.messages) ----------
select public.p4r_como('a9999999-0000-0000-0000-000000000001');
select ok(public.p4r_puede_leer(public.p4r_emp('DEMO-0001')), 'el operador A1 escucha el canal de su empresa');
select ok(not public.p4r_puede_leer('admin'), 'el operador no escucha el canal admin');
select public.p4r_como('b9999999-0000-0000-0000-000000000001');
select ok(not public.p4r_puede_leer(public.p4r_emp('DEMO-0001')), 'el operador B1 no escucha el canal de otra empresa');
select public.p4r_como('c9999999-0000-0000-0000-000000000001');
select ok(not public.p4r_puede_leer(public.p4r_emp('DEMO-0001')), 'un ciudadano no escucha canales de empresa');
select public.p4r_como('d9999999-0000-0000-0000-000000000001');
select ok(public.p4r_puede_leer('admin'), 'el admin escucha el canal admin');
reset role;

-- ---------- 5. cambio de empresa: avisa a la anterior ----------
update incidente set empresa_id = (select id from empresa where nit = 'DEMO-0002')
where id = current_setting('p4r.ie')::uuid;
select ok(exists (select 1 from realtime.messages where topic = public.p4r_emp('DEMO-0001')
                  and event = 'incidente_cambiado' and payload ->> 'empresa_id' = (select id::text from empresa where nit = 'DEMO-0002')),
  'la empresa anterior recibe el aviso de que el incidente se fue');
select ok(public.p4r_msgs(public.p4r_emp('DEMO-0002'), 'incidente_cambiado') >= 1, 'y la nueva también');

select * from finish();
rollback;
