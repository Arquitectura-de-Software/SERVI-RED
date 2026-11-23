-- SERVI-RED | Persona 4 | Pruebas de línea de tiempo y exportación regulatoria
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- ---------- ayudantes ----------
create function public.p4x_como(p_uid uuid) returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.headers', '{"x-forwarded-for":"192.0.2.47"}', true);
  set local role authenticated;
end $$;
create function public.p4x_serv(p text) returns smallint language sql as $$
  select id from public.servicio where tipo = p::public.tipo_servicio $$;
create function public.p4x_punto(p_norte_m double precision) returns extensions.geography language sql as $$
  select extensions.st_setsrid(extensions.st_makepoint(-74.07, 4.65 + p_norte_m / 111320.0), 4326)::extensions.geography $$;
create function public.p4x_inc(p uuid) returns uuid language sql security definer set search_path = '' as $$
  select incidente_id from public.reporte where id = p $$;
create function public.p4x_ie() returns uuid language sql as $$ select current_setting('p4x.ie')::uuid $$;
create function public.p4x_ia() returns uuid language sql as $$ select current_setting('p4x.ia')::uuid $$;
create function public.p4x_tipos(p_inc uuid, p_tipo text) returns int language sql as $$
  select count(*)::int from public.linea_tiempo_incidente(p_inc) where tipo = p_tipo $$;
create function public.p4x_rango_desde() returns date language sql as $$
  select ((now() at time zone 'America/Bogota')::date - 1) $$;
create function public.p4x_rango_hasta() returns date language sql as $$
  select ((now() at time zone 'America/Bogota')::date + 1) $$;

-- ---------- datos ----------
-- A1, A2: energía (empresa demo). B1: acueducto. R1: regulador. C1: ciudadano. D1: admin.
insert into auth.users (id) values
  ('a7777777-0000-0000-0000-000000000001'), ('a7777777-0000-0000-0000-000000000002'),
  ('b7777777-0000-0000-0000-000000000001'), ('e7777777-0000-0000-0000-000000000001'),
  ('c7777777-0000-0000-0000-000000000001'), ('d7777777-0000-0000-0000-000000000001');
select public.promover_usuario('a7777777-0000-0000-0000-000000000001'::uuid, 'operador', (select id from empresa where nit = 'DEMO-0001'), 'Ana Trazas', 'Analista');
select public.promover_usuario('a7777777-0000-0000-0000-000000000002'::uuid, 'operador', (select id from empresa where nit = 'DEMO-0001'), 'Andrés Trazas', 'Técnico');
select public.promover_usuario('b7777777-0000-0000-0000-000000000001'::uuid, 'operador', (select id from empresa where nit = 'DEMO-0002'), 'Beatriz Trazas', 'Analista');
select public.promover_usuario('e7777777-0000-0000-0000-000000000001'::uuid, 'regulador');
select public.promover_usuario('d7777777-0000-0000-0000-000000000001'::uuid, 'admin');

insert into reporte (id, client_request_id, ciudadano_id, servicio_id, municipio_codigo, ubicacion, descripcion) values
  ('17000000-0000-0000-0000-000000000001', gen_random_uuid(), 'c7777777-0000-0000-0000-000000000001', public.p4x_serv('energia'),   '11001', public.p4x_punto(0),   'Soy Juan Pérez, calle 10 # 5-20'),
  ('17000000-0000-0000-0000-000000000002', gen_random_uuid(), 'c7777777-0000-0000-0000-000000000001', public.p4x_serv('energia'),   '11001', public.p4x_punto(100), 'Sin luz desde la mañana'),
  ('17000000-0000-0000-0000-000000000003', gen_random_uuid(), 'c7777777-0000-0000-0000-000000000001', public.p4x_serv('energia'),   '11001', public.p4x_punto(150), 'spam'),
  ('17000000-0000-0000-0000-000000000004', gen_random_uuid(), 'c7777777-0000-0000-0000-000000000001', public.p4x_serv('acueducto'), '11001', public.p4x_punto(0),   'Sin agua');
-- Agrupación asíncrona (ADR-03): se ejecuta el proceso que corre pg_cron.
select private.agrupar_pendientes();
select set_config('p4x.ie', public.p4x_inc('17000000-0000-0000-0000-000000000001')::text, true);
select set_config('p4x.ia', public.p4x_inc('17000000-0000-0000-0000-000000000004')::text, true);

-- Fechas hacia atrás para medir duraciones: reportado hace 6 h, inicio hace 5 h 15 min.
update incidente set creado_en = now() - interval '6 hours', inicio_en = now() - interval '5 hours 15 minutes'
where id = public.p4x_ie();

-- Historia del incidente de energía, hecha por A1.
select public.p4x_como('a7777777-0000-0000-0000-000000000001');
select * from public.cambiar_estado_incidente(public.p4x_ie(), 'en_atencion', 'Cuadrilla en camino');
select * from public.asignar_incidente(public.p4x_ie(), 'a7777777-0000-0000-0000-000000000002');
update incidente set prioridad = 1 where id = public.p4x_ie();
select * from public.moderar_reporte('17000000-0000-0000-0000-000000000003', 'rechazada', 'Contenido sin relación');
select * from public.cambiar_estado_incidente(public.p4x_ie(), 'restablecido');
select * from public.cambiar_estado_incidente(public.p4x_ie(), 'en_atencion');   -- reabierto
select * from public.cambiar_estado_incidente(public.p4x_ie(), 'restablecido');
select * from public.cambiar_estado_incidente(public.p4x_ie(), 'cerrado');

-- ---------- 1. línea de tiempo ----------
select is((select tipo from public.linea_tiempo_incidente(public.p4x_ie()) limit 1), 'incidente_creado',
  'la línea de tiempo empieza con la creación del incidente');
select is(public.p4x_tipos(public.p4x_ie(), 'reporte_vinculado'), 3, 'muestra los 3 reportes que llegaron');
select is(public.p4x_tipos(public.p4x_ie(), 'estado_cambiado'), 5, 'muestra los 5 cambios de estado');
select is(public.p4x_tipos(public.p4x_ie(), 'asignacion_cambiada'), 1, 'muestra la asignación');
select is(public.p4x_tipos(public.p4x_ie(), 'prioridad_cambiada'), 1, 'muestra el cambio de prioridad');
select is(public.p4x_tipos(public.p4x_ie(), 'respuesta'), 1, 'muestra la respuesta del operador');
select is(public.p4x_tipos(public.p4x_ie(), 'reporte_desvinculado'), 1, 'muestra el reporte descartado');
select is((select descripcion from public.linea_tiempo_incidente(public.p4x_ie()) where tipo = 'reporte_moderado'),
  'Reporte rechazado: Contenido sin relación', 'muestra el motivo de la moderación');
select is((select actor_nombre from public.linea_tiempo_incidente(public.p4x_ie()) where tipo = 'respuesta'),
  'Ana Trazas', 'las acciones del operador muestran su nombre');
select is((select descripcion from public.linea_tiempo_incidente(public.p4x_ie()) where tipo = 'asignacion_cambiada'),
  'Asignado a Andrés Trazas', 'la asignación dice a quién');
select is((select string_agg(detalle ->> 'hacia', ',' order by ocurrido_en, orden)
           from public.linea_tiempo_incidente(public.p4x_ie()) where tipo = 'estado_cambiado'),
  'en_atencion,restablecido,en_atencion,restablecido,cerrado', 'los estados salen en orden');
select ok(not exists (
    select 1 from public.linea_tiempo_incidente(public.p4x_ie()) t
    where t::text like '%c7777777%' or t::text like '%Juan Pérez%' or t::text like '%calle 10%'),
  'la línea de tiempo no expone al ciudadano ni la descripción de su reporte');

select throws_ok($$select * from public.linea_tiempo_incidente(gen_random_uuid())$$, 'PT404', null,
  'un incidente inexistente da 404');

select public.p4x_como('b7777777-0000-0000-0000-000000000001');
select throws_ok($$select * from public.linea_tiempo_incidente(public.p4x_ie())$$, '42501', null,
  'un operador de otra empresa no ve la línea de tiempo');
select public.p4x_como('c7777777-0000-0000-0000-000000000001');
select throws_ok($$select * from public.linea_tiempo_incidente(public.p4x_ie())$$, '42501', null,
  'un ciudadano no ve la línea de tiempo');
select public.p4x_como('e7777777-0000-0000-0000-000000000001');
select ok(public.p4x_tipos(public.p4x_ie(), 'estado_cambiado') = 5, 'el regulador ve la línea de tiempo');
select public.p4x_como('d7777777-0000-0000-0000-000000000001');
select ok(public.p4x_tipos(public.p4x_ie(), 'estado_cambiado') = 5, 'el admin ve la línea de tiempo');

-- ---------- 2. exportación ----------
select public.p4x_como('a7777777-0000-0000-0000-000000000001');
select is((select count(*)::int from public.exportar_incidentes(public.p4x_rango_desde(), public.p4x_rango_hasta())), 1,
  'el operador exporta solo los incidentes de su empresa');
select throws_ok(format($$select * from public.exportar_incidentes(%L, %L, null, %L)$$,
    public.p4x_rango_desde(), public.p4x_rango_hasta(), (select id from empresa where nit = 'DEMO-0002')),
  '42501', null, 'el operador no exporta los de otra empresa');
select throws_ok($$select * from public.exportar_incidentes('2026-02-01', '2026-01-01')$$, 'PT400', null,
  'un rango invertido da 400');
select throws_ok($$select * from public.exportar_incidentes('2024-01-01', '2026-01-01')$$, 'PT400', null,
  'un rango de más de un año da 400');

select is((select duracion_horas from public.exportar_incidentes(public.p4x_rango_desde(), public.p4x_rango_hasta())), 5.25,
  'duracion_horas = restablecimiento - inicio');
select is((select horas_hasta_atencion from public.exportar_incidentes(public.p4x_rango_desde(), public.p4x_rango_hasta())), 6.00,
  'horas_hasta_atencion = primera atención - reporte');
select is((select total_reportes || '|' || total_respuestas || '|' || reabierto || '|' || estado || '|' || prioridad
           from public.exportar_incidentes(public.p4x_rango_desde(), public.p4x_rango_hasta())),
  '2|1|sí|cerrado|1', 'conteos, reapertura, estado y prioridad');
select is((select servicio || '|' || empresa_nit || '|' || departamento_dane || '|' || municipio_dane || '|' || municipio
           from public.exportar_incidentes(public.p4x_rango_desde(), public.p4x_rango_hasta())),
  'energia|DEMO-0001|11|11001|Bogotá, D.C.', 'servicio, empresa y códigos DANE');
select ok((select not (to_jsonb(x) ?| array['ciudadano_id', 'descripcion', 'lat', 'lng', 'centroide'])
           from public.exportar_incidentes(public.p4x_rango_desde(), public.p4x_rango_hasta()) x),
  'la exportación no tiene datos personales ni coordenadas');

select public.p4x_como('e7777777-0000-0000-0000-000000000001');
select is((select count(*)::int from public.exportar_incidentes(public.p4x_rango_desde(), public.p4x_rango_hasta())), 2,
  'el regulador exporta todas las empresas');
select is((select count(*)::int from public.exportar_incidentes(public.p4x_rango_desde(), public.p4x_rango_hasta(), public.p4x_serv('acueducto'))), 1,
  'el filtro por servicio funciona');
select is((select count(*)::int from public.exportar_incidentes('2020-01-01', '2020-12-31')), 0,
  'un período sin incidentes devuelve 0 filas');
select is((select reabierto || '|' || coalesce(duracion_horas::text, 'null')
           from public.exportar_incidentes(public.p4x_rango_desde(), public.p4x_rango_hasta(), public.p4x_serv('acueducto'))),
  'no|null', 'un incidente sin restablecer no tiene duración');

select public.p4x_como('c7777777-0000-0000-0000-000000000001');
select throws_ok($$select * from public.exportar_incidentes('2026-01-01', '2026-01-31')$$, '42501', null,
  'un ciudadano no exporta');
reset role;

select ok(exists (select 1 from audit_log where accion = 'exportar'
    and actor_id = 'a7777777-0000-0000-0000-000000000001' and (despues ->> 'filas')::int = 1),
  'cada exportación queda auditada con el usuario y la cantidad de filas');
select is((select despues ->> 'empresa_id' from audit_log where accion = 'exportar'
    and actor_id = 'a7777777-0000-0000-0000-000000000001' order by id limit 1),
  (select id::text from empresa where nit = 'DEMO-0001'), 'la auditoría guarda la empresa que se exportó');

set local role anon;
select throws_ok($$select * from public.exportar_incidentes('2026-01-01', '2026-01-31')$$, '42501', null,
  'anon no puede exportar');
reset role;

select * from finish();
rollback;
