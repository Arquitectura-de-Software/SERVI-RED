-- SERVI-RED | Persona 4 | Pruebas de la gestión de incidentes (estado, asignación, respuestas, vista)
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- ---------- ayudantes ----------
create function public.p4g_como(p_uid uuid) returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.headers', '{"x-forwarded-for":"192.0.2.45"}', true);
  set local role authenticated;
end $$;
create function public.p4g_serv(p text) returns smallint language sql as $$
  select id from public.servicio where tipo = p::public.tipo_servicio $$;
create function public.p4g_punto(p_norte_m double precision) returns extensions.geography language sql as $$
  select extensions.st_setsrid(extensions.st_makepoint(-74.07, 4.65 + p_norte_m / 111320.0), 4326)::extensions.geography $$;
create function public.p4g_inc(p_reporte uuid) returns uuid language sql security definer set search_path = '' as $$
  select incidente_id from public.reporte where id = p_reporte $$;

-- ---------- datos ----------
-- A1, A2: operadores activos de la empresa demo de energía; A3: inactivo.
-- B1: operador de la empresa demo de acueducto. C1: ciudadano. D1: admin.
insert into auth.users (id) values
  ('a5555555-0000-0000-0000-000000000001'), ('a5555555-0000-0000-0000-000000000002'),
  ('a5555555-0000-0000-0000-000000000003'), ('b5555555-0000-0000-0000-000000000001'),
  ('c5555555-0000-0000-0000-000000000001'), ('d5555555-0000-0000-0000-000000000001');
select public.promover_usuario('a5555555-0000-0000-0000-000000000001'::uuid, 'operador', (select id from empresa where nit = 'DEMO-0001'), 'Ana P4', 'Analista');
select public.promover_usuario('a5555555-0000-0000-0000-000000000002'::uuid, 'operador', (select id from empresa where nit = 'DEMO-0001'), 'Andrés P4', 'Técnico');
select public.promover_usuario('a5555555-0000-0000-0000-000000000003'::uuid, 'operador', (select id from empresa where nit = 'DEMO-0001'), 'Inactivo P4', 'Técnico');
select public.promover_usuario('b5555555-0000-0000-0000-000000000001'::uuid, 'operador', (select id from empresa where nit = 'DEMO-0002'), 'Beatriz P4', 'Analista');
select public.promover_usuario('d5555555-0000-0000-0000-000000000001'::uuid, 'admin');
update perfil set activo = false where id = 'a5555555-0000-0000-0000-000000000003';

-- Dos reportes de energía cercanos (un incidente de la empresa demo de energía)
-- y uno de alcantarillado (sin cobertura: incidente sin empresa).
insert into reporte (id, client_request_id, ciudadano_id, servicio_id, municipio_codigo, ubicacion) values
  ('15000000-0000-0000-0000-000000000001', gen_random_uuid(), 'c5555555-0000-0000-0000-000000000001', public.p4g_serv('energia'), '11001', public.p4g_punto(0)),
  ('15000000-0000-0000-0000-000000000002', gen_random_uuid(), 'c5555555-0000-0000-0000-000000000001', public.p4g_serv('energia'), '11001', public.p4g_punto(100)),
  ('15000000-0000-0000-0000-000000000003', gen_random_uuid(), 'c5555555-0000-0000-0000-000000000001', public.p4g_serv('alcantarillado'), '11001', public.p4g_punto(0));
-- Agrupación asíncrona (ADR-03): se ejecuta el proceso que corre pg_cron.
select private.agrupar_pendientes();
select set_config('p4g.ie', public.p4g_inc('15000000-0000-0000-0000-000000000001')::text, true);
select set_config('p4g.ia', public.p4g_inc('15000000-0000-0000-0000-000000000003')::text, true);
create function public.p4g_ie() returns uuid language sql as $$ select current_setting('p4g.ie')::uuid $$;
create function public.p4g_ia() returns uuid language sql as $$ select current_setting('p4g.ia')::uuid $$;

select is(public.p4g_inc('15000000-0000-0000-0000-000000000002'), public.p4g_ie(), 'preparación: los dos reportes de energía están en un incidente');

-- ---------- 1. cambiar_estado_incidente ----------
select public.p4g_como('c5555555-0000-0000-0000-000000000001');
select throws_ok($$select * from public.cambiar_estado_incidente(public.p4g_ie(), 'en_atencion')$$,
  '42501', null, 'un ciudadano no cambia el estado');

select public.p4g_como('b5555555-0000-0000-0000-000000000001');
select throws_ok($$select * from public.cambiar_estado_incidente(public.p4g_ie(), 'en_atencion')$$,
  '42501', null, 'un operador de otra empresa no cambia el estado');

select public.p4g_como('a5555555-0000-0000-0000-000000000001');
select throws_ok($$select * from public.cambiar_estado_incidente(gen_random_uuid(), 'en_atencion')$$,
  'PT404', null, 'un incidente inexistente da 404');
select throws_ok($$select * from public.cambiar_estado_incidente(public.p4g_ie(), 'en_atencion', repeat('x', 2001))$$,
  'PT400', null, 'un mensaje demasiado largo da 400');
select throws_ok($$select * from public.cambiar_estado_incidente(public.p4g_ie(), 'restablecido')$$,
  'PT409', null, 'recibido -> restablecido no está permitido');

select is((select estado::text from public.cambiar_estado_incidente(public.p4g_ie(), 'en_atencion', 'Cuadrilla en camino')),
  'en_atencion', 'el operador pasa el incidente a en_atencion');
select is((select count(*)::int from respuesta where incidente_id = public.p4g_ie() and mensaje = 'Cuadrilla en camino'), 1,
  'el mensaje queda como respuesta del incidente');
select is((select estado::text from public.cambiar_estado_incidente(public.p4g_ie(), 'en_atencion')), 'en_atencion',
  'repetir el mismo estado no falla (idempotente)');
select isnt((select restablecido_en from public.cambiar_estado_incidente(public.p4g_ie(), 'restablecido')), null,
  'al restablecer se fija restablecido_en');
reset role;
select ok(exists (select 1 from evento_outbox where tipo = 'incidente.estado_cambiado'
  and payload ->> 'incidente_id' = public.p4g_ie()::text and payload ->> 'estado_nuevo' = 'restablecido'),
  'el cambio de estado emite incidente.estado_cambiado');
select ok((select count(*) from audit_log where entidad = 'incidente' and entidad_id = public.p4g_ie()
  and actor_id = 'a5555555-0000-0000-0000-000000000001') >= 2, 'los cambios quedan auditados con el operador como actor');

select public.p4g_como('d5555555-0000-0000-0000-000000000001');
select is((select estado::text from public.cambiar_estado_incidente(public.p4g_ie(), 'en_atencion')), 'en_atencion',
  'el admin puede reabrir (restablecido -> en_atencion)');
select throws_ok($$select * from public.cambiar_estado_incidente(public.p4g_ie(), 'en_atencion', 'hola')$$,
  '42501', null, 'el admin no deja respuestas (solo un operador responde)');

-- ---------- 2. asignar_incidente ----------
select public.p4g_como('a5555555-0000-0000-0000-000000000001');
select is((select operador_asignado from public.asignar_incidente(public.p4g_ie(), 'a5555555-0000-0000-0000-000000000002')),
  'a5555555-0000-0000-0000-000000000002'::uuid, 'A1 asigna el incidente a A2');
select throws_ok($$select * from public.asignar_incidente(public.p4g_ie(), 'a5555555-0000-0000-0000-000000000003')$$,
  'PT400', null, 'no se asigna a un operador inactivo');
select throws_ok($$select * from public.asignar_incidente(public.p4g_ie(), 'b5555555-0000-0000-0000-000000000001')$$,
  'PT400', null, 'no se asigna a un operador de otra empresa');
select throws_ok($$select * from public.asignar_incidente(public.p4g_ia(), 'a5555555-0000-0000-0000-000000000002')$$,
  '42501', null, 'un operador no asigna incidentes que no son de su empresa');
select is((select operador_asignado from public.asignar_incidente(public.p4g_ie(), null)), null,
  'pasar null quita la asignación');

select public.p4g_como('b5555555-0000-0000-0000-000000000001');
select throws_ok($$select * from public.asignar_incidente(public.p4g_ie(), 'b5555555-0000-0000-0000-000000000001')$$,
  '42501', null, 'un operador de otra empresa no asigna');

select public.p4g_como('c5555555-0000-0000-0000-000000000001');
select throws_ok($$select * from public.asignar_incidente(public.p4g_ie(), null)$$,
  '42501', null, 'un ciudadano no asigna');

select public.p4g_como('d5555555-0000-0000-0000-000000000001');
select throws_ok($$select * from public.asignar_incidente(public.p4g_ia(), 'a5555555-0000-0000-0000-000000000002')$$,
  'PT409', null, 'no se asigna operador a un incidente sin empresa');

-- ---------- 3. asignar_empresa_incidente ----------
select throws_ok($$select * from public.asignar_empresa_incidente(public.p4g_ia(), (select id from empresa where nit = 'DEMO-0002'))$$,
  'PT400', null, 'no se asigna una empresa que no cubre el servicio en el municipio');
reset role;
insert into empresa_cobertura (empresa_id, servicio_id, municipio_codigo)
values ((select id from empresa where nit = 'DEMO-0002'), public.p4g_serv('alcantarillado'), '11001');
select public.p4g_como('d5555555-0000-0000-0000-000000000001');
select is((select empresa_id from public.asignar_empresa_incidente(public.p4g_ia(), (select id from empresa where nit = 'DEMO-0002'))),
  (select id from empresa where nit = 'DEMO-0002'), 'el admin asigna la empresa a un incidente sin empresa');

select public.p4g_como('a5555555-0000-0000-0000-000000000001');
select throws_ok($$select * from public.asignar_empresa_incidente(public.p4g_ia(), (select id from empresa where nit = 'DEMO-0001'))$$,
  '42501', null, 'un operador no cambia la empresa de un incidente');

-- ---------- 4. responder ----------
select isnt((select respuesta_id from public.responder('Revisando el transformador', public.p4g_ie())), null,
  'el operador responde sobre un incidente de su empresa');
select isnt((select respuesta_id from public.responder('Gracias por el reporte', public.p4g_ie(), '15000000-0000-0000-0000-000000000001')), null,
  'el operador responde a un reporte del incidente');
select throws_ok($$select * from public.responder('   ', public.p4g_ie())$$, 'PT400', null, 'una respuesta vacía da 400');
select throws_ok($$select * from public.responder('hola')$$, 'PT400', null, 'una respuesta sin destino da 400');
select throws_ok($$select * from public.responder('hola', public.p4g_ie(), '15000000-0000-0000-0000-000000000003')$$,
  'PT400', null, 'un reporte de otro incidente da 400');

select public.p4g_como('b5555555-0000-0000-0000-000000000001');
select throws_ok($$select * from public.responder('hola', public.p4g_ie())$$, '42501', null,
  'un operador de otra empresa no responde');

select public.p4g_como('c5555555-0000-0000-0000-000000000001');
select throws_ok($$select * from public.responder('hola', public.p4g_ie())$$, '42501', null, 'un ciudadano no responde');
select is((select count(*)::int from respuesta where reporte_id = '15000000-0000-0000-0000-000000000001'), 1,
  'el ciudadano autor ve la respuesta a su reporte');

-- ---------- 5. vista incidente_operacion ----------
select public.p4g_como('a5555555-0000-0000-0000-000000000001');
select ok((select abs(lat - (4.65 + 50 / 111320.0)) < 0.00001 and abs(lng + 74.07) < 0.00001
           from incidente_operacion where id = public.p4g_ie()), 'la vista entrega lat/lng del centroide');
select is((select total_reportes from incidente_operacion where id = public.p4g_ie()), 2, 'el operador ve los 2 reportes del incidente');
select is((select servicio_tipo::text || '|' || municipio || '|' || empresa from incidente_operacion where id = public.p4g_ie()),
  'energia|Bogotá, D.C.|Operador Demo Energía', 'la vista trae servicio, municipio y empresa');

select public.p4g_como('b5555555-0000-0000-0000-000000000001');
select is((select count(*)::int from incidente_operacion where id = public.p4g_ie()), 0,
  'un operador de otra empresa no ve el incidente en la vista del portal');
select is((select count(*)::int from reporte where incidente_id = public.p4g_ie()), 0,
  'ni sus reportes');

reset role;
set local role anon;
select throws_ok($$select * from public.incidente_operacion$$, '42501', null, 'anon no lee la vista');
reset role;

select * from finish();
rollback;
