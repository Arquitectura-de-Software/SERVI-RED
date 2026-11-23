-- SERVI-RED | Persona 4 | Pruebas de moderación de denuncias y reportes
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- ---------- ayudantes ----------
create function public.p4m_como(p_uid uuid) returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.headers', '{"x-forwarded-for":"192.0.2.46"}', true);
  set local role authenticated;
end $$;
create function public.p4m_serv(p text) returns smallint language sql as $$
  select id from public.servicio where tipo = p::public.tipo_servicio $$;
create function public.p4m_punto(p_norte_m double precision) returns extensions.geography language sql as $$
  select extensions.st_setsrid(extensions.st_makepoint(-74.07, 4.65 + p_norte_m / 111320.0), 4326)::extensions.geography $$;
-- Lecturas como postgres (sin RLS) para verificar efectos.
create function public.p4m_rep(p uuid) returns public.reporte language sql security definer set search_path = '' as $$
  select * from public.reporte where id = p $$;
create function public.p4m_inc(p uuid) returns public.incidente language sql security definer set search_path = '' as $$
  select * from public.incidente where id = p $$;
create function public.p4m_den(p uuid) returns public.estado_denuncia language sql security definer set search_path = '' as $$
  select estado from public.denuncia where id = p $$;

-- ---------- datos ----------
-- A1: operador de energía (empresa demo). B1: operador de acueducto. C1: ciudadano. D1: admin.
insert into auth.users (id) values
  ('a6666666-0000-0000-0000-000000000001'), ('b6666666-0000-0000-0000-000000000001'),
  ('c6666666-0000-0000-0000-000000000001'), ('d6666666-0000-0000-0000-000000000001');
select public.promover_usuario('a6666666-0000-0000-0000-000000000001'::uuid, 'operador', (select id from empresa where nit = 'DEMO-0001'), 'Ana Moderadora', 'Analista');
select public.promover_usuario('b6666666-0000-0000-0000-000000000001'::uuid, 'operador', (select id from empresa where nit = 'DEMO-0002'), 'Beatriz Moderadora', 'Analista');
select public.promover_usuario('d6666666-0000-0000-0000-000000000001'::uuid, 'admin');

-- Denuncias de energía en Bogotá
insert into denuncia (id, client_request_id, servicio_id, municipio_codigo, ubicacion_aprox, descripcion, seguimiento_hash) values
  ('16000000-0000-0000-0000-0000000000d1', gen_random_uuid(), public.p4m_serv('energia'), '11001', public.p4m_punto(0), 'Conexión ilegal en el poste de la esquina', 'hash-p4-d1'),
  ('16000000-0000-0000-0000-0000000000d2', gen_random_uuid(), public.p4m_serv('energia'), '11001', null,               'Medidor manipulado en el edificio vecino',  'hash-p4-d2'),
  ('16000000-0000-0000-0000-0000000000d3', gen_random_uuid(), public.p4m_serv('energia'), '11001', null,               'Cables expuestos cerca del parque central', 'hash-p4-d3');

-- Reportes: r1 y r2 en el mismo incidente; r3 solo en su propio incidente.
insert into reporte (id, client_request_id, ciudadano_id, servicio_id, municipio_codigo, ubicacion) values
  ('16000000-0000-0000-0000-000000000001', gen_random_uuid(), 'c6666666-0000-0000-0000-000000000001', public.p4m_serv('energia'), '11001', public.p4m_punto(0)),
  ('16000000-0000-0000-0000-000000000002', gen_random_uuid(), 'c6666666-0000-0000-0000-000000000001', public.p4m_serv('energia'), '11001', public.p4m_punto(200)),
  ('16000000-0000-0000-0000-000000000003', gen_random_uuid(), 'c6666666-0000-0000-0000-000000000001', public.p4m_serv('energia'), '11001', public.p4m_punto(5000)),
  ('16000000-0000-0000-0000-000000000004', gen_random_uuid(), 'c6666666-0000-0000-0000-000000000001', public.p4m_serv('energia'), '11001', public.p4m_punto(9000));
-- Agrupación asíncrona (ADR-03): se ejecuta el proceso que corre pg_cron.
select private.agrupar_pendientes();
select set_config('p4m.i12', (public.p4m_rep('16000000-0000-0000-0000-000000000001')).incidente_id::text, true);
select set_config('p4m.i3',  (public.p4m_rep('16000000-0000-0000-0000-000000000003')).incidente_id::text, true);
select set_config('p4m.i4',  (public.p4m_rep('16000000-0000-0000-0000-000000000004')).incidente_id::text, true);
select is((public.p4m_rep('16000000-0000-0000-0000-000000000002')).incidente_id::text, current_setting('p4m.i12'),
  'preparación: r1 y r2 están en el mismo incidente');

-- ---------- 1. cola de moderación ----------
select public.p4m_como('a6666666-0000-0000-0000-000000000001');
select is((select count(*)::int from cola_moderacion where tipo = 'denuncia' and id::text like '16000000%'), 3,
  'la cola muestra las 3 denuncias pendientes de su zona');
select is((select count(*)::int from cola_moderacion where tipo = 'reporte' and id::text like '16000000%'), 4,
  'la cola muestra los 4 reportes sin moderar');
select ok((select lat is not null from cola_moderacion where id = '16000000-0000-0000-0000-0000000000d1'),
  'la cola trae la ubicación aproximada de la denuncia');
select hasnt_column('public', 'cola_moderacion', 'seguimiento_hash', 'la cola no expone el hash de seguimiento');
select hasnt_column('public', 'cola_moderacion', 'ciudadano_id', 'la cola no expone al ciudadano');

select public.p4m_como('b6666666-0000-0000-0000-000000000001');
select is((select count(*)::int from cola_moderacion where id::text like '16000000%'), 0,
  'un operador de otro servicio no ve nada de esa cola');

-- ---------- 2. moderar_denuncia ----------
select throws_ok($$select * from public.moderar_denuncia('16000000-0000-0000-0000-0000000000d1', 'aprobada')$$,
  'PT404', null, 'un operador sin cobertura no modera la denuncia');

select public.p4m_como('c6666666-0000-0000-0000-000000000001');
select throws_ok($$select * from public.moderar_denuncia('16000000-0000-0000-0000-0000000000d1', 'aprobada')$$,
  '42501', null, 'un ciudadano no modera');

select public.p4m_como('d6666666-0000-0000-0000-000000000001');
select throws_ok($$select * from public.moderar_denuncia('16000000-0000-0000-0000-0000000000d1', 'aprobada')$$,
  '42501', null, 'el admin no modera (la validación necesita un operador)');

select public.p4m_como('a6666666-0000-0000-0000-000000000001');
select throws_ok($$select * from public.moderar_denuncia('16000000-0000-0000-0000-0000000000d1', 'rechazada')$$,
  'PT400', null, 'rechazar sin motivo da 400');
select throws_ok($$select * from public.moderar_denuncia('16000000-0000-0000-0000-0000000000d1', 'rechazada', '   ')$$,
  'PT400', null, 'un motivo en blanco da 400');

select is((select estado_denuncia::text from public.moderar_denuncia('16000000-0000-0000-0000-0000000000d1', 'pendiente', 'Revisando con la cuadrilla')),
  'en_revision', 'pendiente pasa la denuncia a en_revision');
select is((select estado_denuncia::text from public.moderar_denuncia('16000000-0000-0000-0000-0000000000d1', 'aprobada', 'Confirmado en sitio')),
  'validada', 'aprobada pasa la denuncia a validada');
select throws_ok($$select * from public.moderar_denuncia('16000000-0000-0000-0000-0000000000d1', 'rechazada', 'cambio de opinión')$$,
  'PT409', null, 'una denuncia ya moderada no se vuelve a moderar');
select is((select estado_denuncia::text from public.moderar_denuncia('16000000-0000-0000-0000-0000000000d2', 'rechazada', 'No se encontró evidencia')),
  'descartada', 'rechazada pasa la denuncia a descartada');

select is((select count(*)::int from validacion where denuncia_id = '16000000-0000-0000-0000-0000000000d1'), 2,
  'cada decisión queda en el historial de validaciones');
select is((select ultima_decision::text from cola_moderacion where id = '16000000-0000-0000-0000-0000000000d3'), null,
  'una denuncia sin decisiones no tiene última decisión');
select is((select count(*)::int from cola_moderacion where tipo = 'denuncia' and id::text like '16000000%'), 1,
  'las denuncias moderadas salen de la cola');
reset role;
select is(public.p4m_den('16000000-0000-0000-0000-0000000000d1')::text, 'validada', 'el estado queda guardado');
select ok(exists (select 1 from evento_outbox where tipo = 'denuncia.estado_cambiado'
  and payload ->> 'denuncia_id' = '16000000-0000-0000-0000-0000000000d2' and payload ->> 'estado_nuevo' = 'descartada'),
  'la moderación emite denuncia.estado_cambiado');
select ok(not exists (select 1 from evento_outbox where tipo = 'denuncia.estado_cambiado'
  and payload::text like '%hash-p4%'), 'el evento no lleva el hash de seguimiento');

-- ---------- 3. moderar_reporte ----------
select public.p4m_como('b6666666-0000-0000-0000-000000000001');
select throws_ok($$select * from public.moderar_reporte('16000000-0000-0000-0000-000000000001', 'aprobada')$$,
  'PT404', null, 'un operador sin cobertura no modera el reporte');

select public.p4m_como('a6666666-0000-0000-0000-000000000001');
select throws_ok($$select * from public.moderar_reporte('16000000-0000-0000-0000-000000000001', 'pendiente')$$,
  'PT400', null, 'un reporte no queda pendiente: se aprueba o se rechaza');
select throws_ok($$select * from public.moderar_reporte('16000000-0000-0000-0000-000000000001', 'rechazada')$$,
  'PT400', null, 'rechazar un reporte sin motivo da 400');

select is((select estado_reporte::text from public.moderar_reporte('16000000-0000-0000-0000-000000000001', 'aprobada')),
  'vinculado', 'aprobar no cambia el estado del reporte');
select is((select count(*)::int from cola_moderacion where id = '16000000-0000-0000-0000-000000000001'), 0,
  'el reporte aprobado sale de la cola');

-- Rechazar r2: sale del incidente y el centroide vuelve a r1.
select is((select estado_reporte::text || '|' || coalesce(incidente_cerrado::text, '')
            from public.moderar_reporte('16000000-0000-0000-0000-000000000002', 'rechazada', 'Reporte duplicado de prueba')),
  'descartado|false', 'rechazar un reporte lo descarta sin cerrar un incidente que tiene otros reportes');
reset role;
select is((public.p4m_rep('16000000-0000-0000-0000-000000000002')).incidente_id, null, 'el reporte rechazado queda sin incidente');
select ok(extensions.st_distance((public.p4m_inc(current_setting('p4m.i12')::uuid)).centroide, public.p4m_punto(0)) < 1,
  'el centroide se recalcula sin el reporte rechazado');

-- Rechazar r3 (único de su incidente, en 'recibido'): el incidente se cierra.
select public.p4m_como('a6666666-0000-0000-0000-000000000001');
select is((select incidente_cerrado from public.moderar_reporte('16000000-0000-0000-0000-000000000003', 'rechazada', 'Spam')),
  true, 'si el incidente queda sin reportes y estaba recibido, se cierra');
reset role;
select is((public.p4m_inc(current_setting('p4m.i3')::uuid)).estado::text, 'cerrado', 'el incidente vacío quedó cerrado');

-- r4: su incidente ya está en atención; al rechazarlo el incidente NO se cierra.
update incidente set estado = 'en_atencion' where id = current_setting('p4m.i4')::uuid;
select public.p4m_como('a6666666-0000-0000-0000-000000000001');
select is((select incidente_cerrado from public.moderar_reporte('16000000-0000-0000-0000-000000000004', 'rechazada', 'Ubicación equivocada')),
  false, 'un incidente en atención no se cierra solo');
select throws_ok($$select * from public.moderar_reporte('16000000-0000-0000-0000-000000000004', 'aprobada')$$,
  'PT409', null, 'un reporte descartado no se vuelve a moderar');
reset role;

select ok(exists (select 1 from evento_outbox where tipo = 'reporte.estado_cambiado'
  and payload ->> 'reporte_id' = '16000000-0000-0000-0000-000000000002' and payload ->> 'estado_nuevo' = 'descartado'),
  'rechazar un reporte emite reporte.estado_cambiado (la app lo notifica)');
select ok((select count(*) from audit_log where entidad = 'validacion'
  and actor_id = 'a6666666-0000-0000-0000-000000000001') >= 6, 'las validaciones quedan auditadas con el moderador');

-- ---------- 3b. reintentos con client_request_id ----------
select public.p4m_como('a6666666-0000-0000-0000-000000000001');
select set_config('p4m.v_d3', (select validacion_id::text from public.moderar_denuncia(
  '16000000-0000-0000-0000-0000000000d3', 'aprobada', 'Confirmado', '16000000-0000-0000-0000-00000000c001')), true);
select is((select validacion_id::text || '|' || estado_denuncia from public.moderar_denuncia(
  '16000000-0000-0000-0000-0000000000d3', 'aprobada', 'Confirmado', '16000000-0000-0000-0000-00000000c001')),
  current_setting('p4m.v_d3') || '|validada', 'un reintento de moderar_denuncia devuelve la misma validación, sin 409');
select is((select count(*)::int from validacion where denuncia_id = '16000000-0000-0000-0000-0000000000d3'), 1,
  'el reintento no duplica la validación');
select throws_ok($$select * from public.moderar_denuncia('16000000-0000-0000-0000-0000000000d3', 'aprobada')$$,
  'PT409', null, 'sin client_request_id, volver a moderar sí da 409');
select throws_ok($$select * from public.moderar_reporte('16000000-0000-0000-0000-000000000001', 'aprobada', null,
  '16000000-0000-0000-0000-00000000c001')$$, 'PT409', null, 'el mismo client_request_id en otra decisión da 409');

-- Reintento de un rechazo: devuelve el incidente del que salió el reporte.
reset role;
insert into reporte (id, client_request_id, ciudadano_id, servicio_id, municipio_codigo, ubicacion) values
  ('16000000-0000-0000-0000-000000000005', gen_random_uuid(), 'c6666666-0000-0000-0000-000000000001',
   public.p4m_serv('energia'), '11001', public.p4m_punto(15000));
select private.agrupar_pendientes();
select set_config('p4m.i5', (public.p4m_rep('16000000-0000-0000-0000-000000000005')).incidente_id::text, true);
select public.p4m_como('a6666666-0000-0000-0000-000000000001');
select set_config('p4m.v_r5', (select validacion_id::text from public.moderar_reporte(
  '16000000-0000-0000-0000-000000000005', 'rechazada', 'Falso', '16000000-0000-0000-0000-00000000c005')), true);
select is((select validacion_id::text || '|' || estado_reporte || '|' || incidente_id || '|' || incidente_cerrado
           from public.moderar_reporte('16000000-0000-0000-0000-000000000005', 'rechazada', 'Falso',
                                       '16000000-0000-0000-0000-00000000c005')),
  current_setting('p4m.v_r5') || '|descartado|' || current_setting('p4m.i5') || '|true',
  'un reintento de moderar_reporte devuelve la decisión previa con su incidente');
reset role;
select is((select count(*)::int from validacion where reporte_id = '16000000-0000-0000-0000-000000000005'), 1,
  'el reintento no duplica la validación del reporte');

-- ---------- 4. permisos ----------
set local role anon;
select throws_ok($$select * from public.cola_moderacion$$, '42501', null, 'anon no lee la cola');
select throws_ok($$select * from public.moderar_denuncia('16000000-0000-0000-0000-0000000000d3', 'aprobada')$$,
  '42501', null, 'anon no puede moderar');
reset role;

select * from finish();
rollback;
