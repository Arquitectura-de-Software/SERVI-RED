begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- ---------- ayudantes ----------
create function public.t_como(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.headers', '{"x-forwarded-for":"192.0.2.12"}', true);
  set local role authenticated;
end $$;
create function public.t_filas(p_sql text) returns bigint language plpgsql as $$
declare n bigint;
begin
  execute 'select count(*) from (' || p_sql || ') q' into n;
  return n;
exception when insufficient_privilege then return 0;
end $$;
create function public.t_dml(p_sql text) returns text language plpgsql as $$
declare n bigint;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return 'ok:' || n;
exception when others then return 'error:' || sqlstate;
end $$;
create function public.t_serv(p text) returns smallint language sql as $$
  select id from public.servicio where tipo = p::public.tipo_servicio $$;
create function public.t_punto() returns extensions.geography language sql as $$
  select extensions.st_setsrid(extensions.st_makepoint(-74.07, 4.65), 4326)::extensions.geography $$;

-- ---------- datos ----------
-- A1, A2, A3: operadores de la empresa A. B1: operador de la empresa B. C1: ciudadano.
insert into auth.users (id) values
  ('a1111111-1111-1111-1111-111111111111'),
  ('a2222222-2222-2222-2222-222222222222'),
  ('a3333333-3333-3333-3333-333333333333'),
  ('b1111111-1111-1111-1111-111111111111'),
  ('c1111111-1111-1111-1111-111111111111');

insert into empresa (id, nombre, nit, tipo_entidad) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Empresa Test A', 'TEST-A', 'Empresa de servicios publicos'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Empresa Test B', 'TEST-B', 'Empresa de servicios publicos');

-- A cubre energía en Bogotá (11001); B cubre energía en Medellín (05001)
insert into empresa_cobertura (empresa_id, servicio_id, municipio_codigo) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', public.t_serv('energia'), '11001'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', public.t_serv('energia'), '05001');

select public.promover_usuario('a1111111-1111-1111-1111-111111111111'::uuid, 'operador', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, 'Operador A1', 'Analista');
select public.promover_usuario('a2222222-2222-2222-2222-222222222222'::uuid, 'operador', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, 'Operador A2', 'Analista');
select public.promover_usuario('a3333333-3333-3333-3333-333333333333'::uuid, 'operador', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, 'Operador A3', 'Analista');
select public.promover_usuario('b1111111-1111-1111-1111-111111111111'::uuid, 'operador', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid, 'Operador B1', 'Analista');
update perfil set activo = false where id = 'a3333333-3333-3333-3333-333333333333';

-- R1: energía/Bogotá (lo cubre A). R2: energía/Medellín (lo cubre B). R3: acueducto/Bogotá (nadie de prueba).
insert into reporte (id, client_request_id, ciudadano_id, servicio_id, municipio_codigo, ubicacion) values
  ('10000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 'c1111111-1111-1111-1111-111111111111', public.t_serv('energia'),   '11001', public.t_punto()),
  ('10000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000002', 'c1111111-1111-1111-1111-111111111111', public.t_serv('energia'),   '05001', public.t_punto()),
  ('10000000-0000-0000-0000-000000000003', '40000000-0000-0000-0000-000000000003', 'c1111111-1111-1111-1111-111111111111', public.t_serv('acueducto'), '11001', public.t_punto());

insert into incidente (id, servicio_id, empresa_id, municipio_codigo) values
  ('20000000-0000-0000-0000-000000000001', public.t_serv('energia'), 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11001'),
  ('20000000-0000-0000-0000-000000000002', public.t_serv('energia'), 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '05001');

insert into denuncia (id, client_request_id, servicio_id, municipio_codigo, descripcion, seguimiento_hash) values
  ('30000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000004', public.t_serv('energia'), '11001', 'Descripcion de prueba D1', 'hash-d1'),
  ('30000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000005', public.t_serv('energia'), '05001', 'Descripcion de prueba D2', 'hash-d2');

-- ---------- operador A1 ----------
select public.t_como('a1111111-1111-1111-1111-111111111111');

select is(public.t_filas($$select 1 from public.reporte where id = '10000000-0000-0000-0000-000000000001'$$), 1::bigint, 'A1 ve el reporte que su empresa cubre');
select is(public.t_filas($$select 1 from public.reporte where id = '10000000-0000-0000-0000-000000000002'$$), 0::bigint, 'A1 no ve reportes de otro municipio');
select is(public.t_filas($$select 1 from public.reporte where id = '10000000-0000-0000-0000-000000000003'$$), 0::bigint, 'A1 no ve reportes de un servicio que no cubre');

select is(public.t_dml($$update public.reporte set descripcion = 'cambiada' where id = '10000000-0000-0000-0000-000000000001'$$), 'error:42501', 'A1 no edita la descripción de un reporte');
select is(public.t_dml($$update public.reporte set ubicacion = public.t_punto() where id = '10000000-0000-0000-0000-000000000001'$$), 'error:42501', 'A1 no edita la ubicación de un reporte');
select is(public.t_dml($$update public.reporte set estado = 'vinculado' where id = '10000000-0000-0000-0000-000000000001'$$), 'ok:1', 'A1 cambia el estado de un reporte que cubre');
select is(public.t_dml($$update public.reporte set estado = 'vinculado' where id = '10000000-0000-0000-0000-000000000002'$$), 'ok:0', 'A1 no gestiona reportes de otra zona');

select is(public.t_filas($$select 1 from public.denuncia where id = '30000000-0000-0000-0000-000000000001'$$), 1::bigint, 'A1 ve la denuncia que cubre');
select is(public.t_filas($$select 1 from public.denuncia where id = '30000000-0000-0000-0000-000000000002'$$), 0::bigint, 'A1 no ve denuncias de otra zona');
select is(public.t_dml($$update public.denuncia set estado = 'en_revision' where id = '30000000-0000-0000-0000-000000000001'$$), 'ok:1', 'A1 cambia el estado de una denuncia que cubre');
select is(public.t_dml($$update public.denuncia set descripcion = 'cambiada' where id = '30000000-0000-0000-0000-000000000001'$$), 'error:42501', 'A1 no edita el texto de una denuncia');
select is(public.t_dml($$update public.denuncia set estado = 'validada' where id = '30000000-0000-0000-0000-000000000002'$$), 'ok:0', 'A1 no gestiona denuncias de otra zona');

select is(public.t_filas($$select 1 from public.incidente where id in ('20000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002')$$), 2::bigint, 'cualquier sesión ve los incidentes');
select is(public.t_dml($$update public.incidente set prioridad = 1 where id = '20000000-0000-0000-0000-000000000002'$$), 'ok:0', 'A1 no gestiona incidentes de otra empresa');

select is(public.t_dml($$update public.incidente set estado = 'en_atencion' where id = '20000000-0000-0000-0000-000000000001'$$), 'ok:1', 'transición recibido -> en_atencion');
select is(public.t_dml($$update public.incidente set estado = 'cerrado' where id = '20000000-0000-0000-0000-000000000001'$$), 'error:23514', 'transición en_atencion -> cerrado está prohibida');
select is(public.t_dml($$update public.incidente set estado = 'restablecido' where id = '20000000-0000-0000-0000-000000000001'$$), 'ok:1', 'transición en_atencion -> restablecido');
select is(public.t_dml($$update public.incidente set operador_asignado = 'b1111111-1111-1111-1111-111111111111' where id = '20000000-0000-0000-0000-000000000001'$$), 'error:42501', 'no asigna a un operador de otra empresa');
select is(public.t_dml($$update public.incidente set operador_asignado = 'a2222222-2222-2222-2222-222222222222' where id = '20000000-0000-0000-0000-000000000001'$$), 'ok:1', 'asigna a un operador de su empresa');
select is(public.t_dml($$update public.incidente set empresa_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' where id = '20000000-0000-0000-0000-000000000001'$$), 'error:42501', 'no puede cambiar la empresa de un incidente');

select is(public.t_dml($$insert into public.incidente (id, servicio_id, empresa_id, municipio_codigo)
  values ('20000000-0000-0000-0000-000000000003', public.t_serv('energia'), 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11001')$$), 'ok:1', 'crea un incidente de su empresa en su zona');
select is(public.t_dml($$insert into public.incidente (servicio_id, empresa_id, municipio_codigo)
  values (public.t_serv('energia'), 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '05001')$$), 'error:42501', 'no crea incidentes en un municipio que no cubre');
select is(public.t_dml($$insert into public.incidente (servicio_id, empresa_id, municipio_codigo)
  values (public.t_serv('energia'), 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11001')$$), 'error:42501', 'no crea incidentes a nombre de otra empresa');

select is(public.t_dml($$insert into public.respuesta (incidente_id, operador_id, mensaje)
  values ('20000000-0000-0000-0000-000000000001', 'a1111111-1111-1111-1111-111111111111', 'Cuadrilla en camino')$$), 'ok:1', 'responde sobre un incidente de su empresa');
select is(public.t_dml($$insert into public.respuesta (incidente_id, operador_id, mensaje)
  values ('20000000-0000-0000-0000-000000000001', 'b1111111-1111-1111-1111-111111111111', 'Suplantacion')$$), 'error:42501', 'no responde a nombre de otro operador');
select is(public.t_dml($$insert into public.respuesta (incidente_id, operador_id, mensaje)
  values ('20000000-0000-0000-0000-000000000002', 'a1111111-1111-1111-1111-111111111111', 'Fuera de zona')$$), 'error:42501', 'no responde sobre incidentes de otra empresa');
select is(public.t_dml($$insert into public.respuesta (reporte_id, operador_id, mensaje)
  values ('10000000-0000-0000-0000-000000000001', 'a1111111-1111-1111-1111-111111111111', 'Recibimos su reporte')$$), 'ok:1', 'responde sobre un reporte que cubre');

select is(public.t_dml($$insert into public.validacion (id, reporte_id, operador_id)
  values ('50000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'a1111111-1111-1111-1111-111111111111')$$), 'ok:1', 'valida un reporte que cubre');
select is(public.t_dml($$insert into public.validacion (reporte_id, operador_id)
  values ('10000000-0000-0000-0000-000000000002', 'a1111111-1111-1111-1111-111111111111')$$), 'error:42501', 'no valida reportes de otra zona');
select is(public.t_dml($$insert into public.validacion (denuncia_id, operador_id)
  values ('30000000-0000-0000-0000-000000000001', 'a1111111-1111-1111-1111-111111111111')$$), 'ok:1', 'valida una denuncia que cubre');
select is(public.t_dml($$insert into public.validacion (denuncia_id, operador_id)
  values ('30000000-0000-0000-0000-000000000002', 'a1111111-1111-1111-1111-111111111111')$$), 'error:42501', 'no valida denuncias de otra zona');
select is(public.t_dml($$update public.validacion set estado = 'aprobada' where id = '50000000-0000-0000-0000-000000000001'$$), 'ok:1', 'edita su propia validación');

select is(public.t_filas($$select 1 from public.operador where id in ('a1111111-1111-1111-1111-111111111111','a2222222-2222-2222-2222-222222222222','b1111111-1111-1111-1111-111111111111')$$), 2::bigint, 've operadores de su empresa, no de otras');
select is(public.t_filas($$select 1 from public.perfil$$), 1::bigint, 'solo ve su propio perfil');
select is(public.t_dml($$update public.perfil set rol = 'admin' where id = 'a1111111-1111-1111-1111-111111111111'$$), 'ok:0', 'no puede cambiarse el rol');
select is(public.t_filas($$select 1 from public.audit_log$$), 0::bigint, 'no lee audit_log');
select is(public.t_filas($$select 1 from public.evento_outbox$$), 0::bigint, 'no lee evento_outbox');

-- ---------- operador A2 (misma empresa) ----------
reset role;
select public.t_como('a2222222-2222-2222-2222-222222222222');
select is(public.t_filas($$select 1 from public.validacion where id = '50000000-0000-0000-0000-000000000001'$$), 1::bigint, 'A2 ve validaciones de su empresa');
select is(public.t_dml($$update public.validacion set estado = 'rechazada' where id = '50000000-0000-0000-0000-000000000001'$$), 'ok:0', 'A2 no edita validaciones de A1');

-- ---------- operador B1 (otra empresa) ----------
reset role;
select public.t_como('b1111111-1111-1111-1111-111111111111');
select is(public.t_filas($$select 1 from public.validacion where id = '50000000-0000-0000-0000-000000000001'$$), 0::bigint, 'B1 no ve validaciones de otra empresa');
select is(public.t_filas($$select 1 from public.reporte where id = '10000000-0000-0000-0000-000000000001'$$), 0::bigint, 'B1 no ve reportes de A');
select is(public.t_dml($$update public.incidente set prioridad = 1 where id = '20000000-0000-0000-0000-000000000001'$$), 'ok:0', 'B1 no gestiona incidentes de A');
select is(public.t_filas($$select 1 from public.respuesta where incidente_id = '20000000-0000-0000-0000-000000000001'$$), 0::bigint, 'B1 no ve respuestas de A');

-- ---------- operador inactivo (A3) ----------
reset role;
select public.t_como('a3333333-3333-3333-3333-333333333333');
select is(public.t_filas($$select 1 from public.reporte where id = '10000000-0000-0000-0000-000000000001'$$), 0::bigint, 'un operador inactivo no ve nada');

-- ---------- ciudadano ----------
reset role;
select public.t_como('c1111111-1111-1111-1111-111111111111');
select is(public.t_filas($$select 1 from public.respuesta where reporte_id = '10000000-0000-0000-0000-000000000001'$$), 1::bigint, 'el ciudadano ve la respuesta a su reporte');
select is(public.t_filas($$select 1 from public.respuesta where incidente_id = '20000000-0000-0000-0000-000000000001'$$), 0::bigint, 'el ciudadano no ve respuestas internas de incidentes');
select is(public.t_dml($$insert into public.respuesta (reporte_id, operador_id, mensaje)
  values ('10000000-0000-0000-0000-000000000001', 'a1111111-1111-1111-1111-111111111111', 'Suplantacion')$$), 'error:42501', 'el ciudadano no responde como operador');
select is(public.t_dml($$insert into public.validacion (reporte_id, operador_id)
  values ('10000000-0000-0000-0000-000000000001', 'a1111111-1111-1111-1111-111111111111')$$), 'error:42501', 'el ciudadano no valida reportes');

-- ---------- comprobaciones finales ----------
reset role;
select is((select estado::text from incidente where id = '20000000-0000-0000-0000-000000000001'), 'restablecido', 'el incidente quedó restablecido');
select ok((select restablecido_en is not null from incidente where id = '20000000-0000-0000-0000-000000000001'), 'el trigger fijó restablecido_en');
select is((select operador_asignado from incidente where id = '20000000-0000-0000-0000-000000000001'), 'a2222222-2222-2222-2222-222222222222'::uuid, 'el incidente quedó asignado a A2');
select is((select rol::text from perfil where id = 'a1111111-1111-1111-1111-111111111111'), 'operador', 'el rol de A1 no cambió');

select * from finish();
rollback;