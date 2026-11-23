-- SERVI-RED | Persona 4 | Pruebas de ajustes de operación
-- (reintentos, difusión de respuestas, priorización, vista y métrica)
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- ---------- ayudantes ----------
create function public.p4j_como(p_uid uuid) returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.headers', '{"x-forwarded-for":"192.0.2.48"}', true);
  set local role authenticated;
end $$;
create function public.p4j_serv(p text) returns smallint language sql as $$
  select id from public.servicio where tipo = p::public.tipo_servicio $$;
create function public.p4j_punto(p_norte_m double precision) returns extensions.geography language sql as $$
  select extensions.st_setsrid(extensions.st_makepoint(-74.07, 4.65 + p_norte_m / 111320.0), 4326)::extensions.geography $$;
create function public.p4j_inc(p_reporte uuid) returns uuid language sql security definer set search_path = '' as $$
  select incidente_id from public.reporte where id = p_reporte $$;
create function public.p4j_resp(p_mensaje text) returns integer language sql security definer set search_path = '' as $$
  select count(*)::int from public.respuesta where mensaje = p_mensaje $$;
create function public.p4j_hoy() returns date language sql as $$
  select (now() at time zone 'America/Bogota')::date $$;

-- ---------- datos ----------
-- A1: operador de energía. B1: operador de acueducto. C1, C2: ciudadanos. D1: admin. E1: regulador.
insert into auth.users (id) values
  ('a8888888-0000-0000-0000-000000000001'), ('b8888888-0000-0000-0000-000000000001'),
  ('c8888888-0000-0000-0000-000000000001'), ('c8888888-0000-0000-0000-000000000002'),
  ('d8888888-0000-0000-0000-000000000001'), ('e8888888-0000-0000-0000-000000000001');
select public.promover_usuario('a8888888-0000-0000-0000-000000000001'::uuid, 'operador', (select id from empresa where nit = 'DEMO-0001'), 'Ana Ajustes', 'Analista');
select public.promover_usuario('b8888888-0000-0000-0000-000000000001'::uuid, 'operador', (select id from empresa where nit = 'DEMO-0002'), 'Beatriz Ajustes', 'Analista');
select public.promover_usuario('d8888888-0000-0000-0000-000000000001'::uuid, 'admin');
select public.promover_usuario('e8888888-0000-0000-0000-000000000001'::uuid, 'regulador');

-- Tres reportes de energía cercanos (r1 y r3 de C1, r2 de C2), uno lejano y uno
-- de alcantarillado (sin cobertura: incidente sin empresa).
insert into reporte (id, client_request_id, ciudadano_id, servicio_id, municipio_codigo, ubicacion) values
  ('18000000-0000-0000-0000-000000000001', gen_random_uuid(), 'c8888888-0000-0000-0000-000000000001', public.p4j_serv('energia'), '11001', public.p4j_punto(0)),
  ('18000000-0000-0000-0000-000000000002', gen_random_uuid(), 'c8888888-0000-0000-0000-000000000002', public.p4j_serv('energia'), '11001', public.p4j_punto(100)),
  ('18000000-0000-0000-0000-000000000003', gen_random_uuid(), 'c8888888-0000-0000-0000-000000000001', public.p4j_serv('energia'), '11001', public.p4j_punto(200)),
  ('18000000-0000-0000-0000-000000000004', gen_random_uuid(), 'c8888888-0000-0000-0000-000000000001', public.p4j_serv('energia'), '11001', public.p4j_punto(20000)),
  ('18000000-0000-0000-0000-000000000005', gen_random_uuid(), 'c8888888-0000-0000-0000-000000000001', public.p4j_serv('alcantarillado'), '11001', public.p4j_punto(0));
select private.agrupar_pendientes();
select set_config('p4j.ie',  public.p4j_inc('18000000-0000-0000-0000-000000000001')::text, true);
select set_config('p4j.ie2', public.p4j_inc('18000000-0000-0000-0000-000000000004')::text, true);
create function public.p4j_ie()  returns uuid language sql as $$ select current_setting('p4j.ie')::uuid $$;
create function public.p4j_ie2() returns uuid language sql as $$ select current_setting('p4j.ie2')::uuid $$;
select is(public.p4j_inc('18000000-0000-0000-0000-000000000003'), public.p4j_ie(), 'preparación: 3 reportes en un incidente');

-- ---------- 1. responder con reintento ----------
select public.p4j_como('a8888888-0000-0000-0000-000000000001');
select set_config('p4j.r1', (select respuesta_id::text from public.responder('Revisando la zona', public.p4j_ie(), null,
  '18000000-0000-0000-0000-00000000c001')), true);
select is((select respuesta_id::text from public.responder('Revisando la zona', public.p4j_ie(), null,
  '18000000-0000-0000-0000-00000000c001')), current_setting('p4j.r1'), 'un reintento de responder devuelve la misma respuesta');
select is(public.p4j_resp('Revisando la zona'), 1, 'el reintento no duplica la respuesta');
select throws_ok($$select * from public.responder('Otro mensaje', null, '18000000-0000-0000-0000-000000000001',
  '18000000-0000-0000-0000-00000000c001')$$, 'PT409', null, 'el mismo client_request_id para otra respuesta da 409');

-- ---------- 2. difusión a los ciudadanos (p_a_reportes) ----------
select is((select reportes_notificados from public.responder('Cuadrilla en camino', public.p4j_ie(), null,
  '18000000-0000-0000-0000-00000000c002', true)), 3, 'la difusión notifica a los 3 reportes vinculados');
select is(public.p4j_resp('Cuadrilla en camino'), 4, 'queda la respuesta del incidente y una por reporte');
select is((select reportes_notificados from public.responder('Cuadrilla en camino', public.p4j_ie(), null,
  '18000000-0000-0000-0000-00000000c002', true)), 3, 'un reintento de la difusión devuelve lo mismo');
select is(public.p4j_resp('Cuadrilla en camino'), 4, 'y no vuelve a difundir');
select throws_ok($$select * from public.responder('x', public.p4j_ie(), '18000000-0000-0000-0000-000000000001', null, true)$$,
  'PT400', null, 'la difusión se pide sobre el incidente, no sobre un reporte');
select throws_ok($$select * from public.responder('x', null, '18000000-0000-0000-0000-000000000001', null, true)$$,
  'PT400', null, 'la difusión exige el incidente');

select is((select count(*)::int from public.linea_tiempo_incidente(public.p4j_ie())
           where tipo = 'respuesta' and descripcion = 'Cuadrilla en camino'), 1,
  'la línea de tiempo muestra la difusión una sola vez');
select is((select (detalle ->> 'reportes_notificados')::int from public.linea_tiempo_incidente(public.p4j_ie())
           where tipo = 'respuesta' and descripcion = 'Cuadrilla en camino'), 3,
  'con el número de reportes notificados');
select is((select total_respuestas from public.exportar_incidentes(public.p4j_hoy() - 1, public.p4j_hoy() + 1)
           where incidente_id = public.p4j_ie()), 2, 'el CSV cuenta la difusión como una respuesta');

select public.p4j_como('c8888888-0000-0000-0000-000000000002');
select is((select count(*)::int from respuesta where mensaje = 'Cuadrilla en camino'), 1,
  'el ciudadano C2 ve la respuesta en su reporte');
select is((select count(*)::int from respuesta where mensaje = 'Revisando la zona'), 0,
  'pero no ve las respuestas internas del incidente');
select public.p4j_como('c8888888-0000-0000-0000-000000000001');
select is((select count(*)::int from respuesta where mensaje = 'Cuadrilla en camino'), 2,
  'el ciudadano C1 la ve en sus dos reportes');

-- ---------- 3. cambiar_estado con reintento ----------
select public.p4j_como('a8888888-0000-0000-0000-000000000001');
select set_config('p4j.r3', (select respuesta_id::text from public.cambiar_estado_incidente(public.p4j_ie(), 'en_atencion',
  'Atendiendo', '18000000-0000-0000-0000-00000000c003')), true);
select is((select respuesta_id::text || '|' || estado from public.cambiar_estado_incidente(public.p4j_ie(), 'en_atencion',
  'Atendiendo', '18000000-0000-0000-0000-00000000c003')), current_setting('p4j.r3') || '|en_atencion',
  'un reintento de cambiar_estado devuelve el mismo mensaje y estado');
select is(public.p4j_resp('Atendiendo'), 1, 'el reintento no duplica el mensaje');
select throws_ok($$select * from public.cambiar_estado_incidente(public.p4j_ie2(), 'en_atencion', 'Otro',
  '18000000-0000-0000-0000-00000000c003')$$, 'PT409', null, 'el mismo client_request_id en otro incidente da 409');
select is((select estado::text from incidente where id = public.p4j_ie2()), 'recibido',
  'y el error deshace el cambio de estado');

-- ---------- 4. priorizar ----------
select is((select prioridad from public.priorizar_incidente(public.p4j_ie(), 1::smallint)), 1::smallint,
  'el operador prioriza su incidente');
select is((select prioridad from public.priorizar_incidente(public.p4j_ie(), 1::smallint)), 1::smallint,
  'repetir la misma prioridad no falla');
select throws_ok($$select * from public.priorizar_incidente(public.p4j_ie(), 0::smallint)$$, 'PT400', null, 'prioridad 0 da 400');
select throws_ok($$select * from public.priorizar_incidente(public.p4j_ie(), 6::smallint)$$, 'PT400', null, 'prioridad 6 da 400');
select throws_ok($$select * from public.priorizar_incidente(public.p4j_ie(), null)$$, 'PT400', null, 'sin prioridad da 400');
select throws_ok($$select * from public.priorizar_incidente(gen_random_uuid(), 2::smallint)$$, 'PT404', null, 'un incidente inexistente da 404');
select * from public.cambiar_estado_incidente(public.p4j_ie2(), 'cerrado');
select throws_ok($$select * from public.priorizar_incidente(public.p4j_ie2(), 2::smallint)$$, 'PT409', null, 'un incidente cerrado no se prioriza');
reset role;
select is((select count(*)::int from audit_log where entidad = 'incidente' and entidad_id = public.p4j_ie()
           and accion = 'update' and antes ->> 'prioridad' is distinct from despues ->> 'prioridad'), 1,
  'la prioridad repetida no genera otra fila de auditoría');

select public.p4j_como('b8888888-0000-0000-0000-000000000001');
select throws_ok($$select * from public.priorizar_incidente(public.p4j_ie(), 2::smallint)$$, '42501', null, 'otra empresa no prioriza');
select public.p4j_como('c8888888-0000-0000-0000-000000000001');
select throws_ok($$select * from public.priorizar_incidente(public.p4j_ie(), 2::smallint)$$, '42501', null, 'un ciudadano no prioriza');
select public.p4j_como('d8888888-0000-0000-0000-000000000001');
select is((select prioridad from public.priorizar_incidente(public.p4j_ie(), 2::smallint)), 2::smallint, 'el admin prioriza');

-- ---------- 5. vista incidente_operacion ----------
select public.p4j_como('c8888888-0000-0000-0000-000000000001');
select is((select count(*)::int from incidente_operacion), 0, 'un ciudadano no lee la vista del portal');
select public.p4j_como('e8888888-0000-0000-0000-000000000001');
select ok((select count(*)::int from incidente_operacion where id = public.p4j_ie()) = 1, 'el regulador sí la lee');
select public.p4j_como('b8888888-0000-0000-0000-000000000001');
select is((select count(*)::int from incidente_operacion where id = public.p4j_ie()), 0,
  'un operador de otra empresa no ve el incidente en el portal');
select public.p4j_como('d8888888-0000-0000-0000-000000000001');
select is((select count(*)::int from incidente_operacion
           where id = public.p4j_inc('18000000-0000-0000-0000-000000000005')), 1,
  'el admin ve también los incidentes sin empresa');
select public.p4j_como('a8888888-0000-0000-0000-000000000001');
-- 3 reportes (-1) + energía (-1), recién creado: 5 - 2 = 3.
select is((select prioridad_sugerida from incidente_operacion where id = public.p4j_ie()), 3::smallint,
  'prioridad sugerida: 3 reportes de energía recientes = 3');
select is((select prioridad_sugerida from incidente_operacion where id = public.p4j_ie2()), null,
  'un incidente cerrado no tiene prioridad sugerida');
reset role;
update incidente set creado_en = now() - interval '13 hours' where id = public.p4j_ie();
select public.p4j_como('a8888888-0000-0000-0000-000000000001');
select is((select prioridad_sugerida from incidente_operacion where id = public.p4j_ie()), 1::smallint,
  'con 13 horas abierto la sugerida sube a 1');

-- ---------- 6. métrica de incidentes sin empresa ----------
reset role;
-- metrics_reader no ve el esquema de pgTAP: se lee con su rol y se compara después.
set local role metrics_reader;
select set_config('p4j.metrica', (select total::text from metrics.incidentes_sin_empresa
  where servicio = 'alcantarillado' and municipio_dane = '11001'), true);
reset role;
select is(current_setting('p4j.metrica'), '1', 'metrics_reader ve el incidente de alcantarillado sin empresa');
select public.p4j_como('a8888888-0000-0000-0000-000000000001');
select throws_ok($$select * from metrics.incidentes_sin_empresa$$, '42501', null, 'un cliente no lee la métrica');
reset role;

select * from finish();
rollback;
