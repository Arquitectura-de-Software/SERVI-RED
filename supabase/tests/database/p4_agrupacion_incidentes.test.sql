-- SERVI-RED | Persona 4 | Pruebas de la agrupación automática de reportes
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- ---------- ayudantes ----------
create function public.p4t_como(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.headers', '{"x-forwarded-for":"192.0.2.44"}', true);
  set local role authenticated;
end $$;
create function public.p4t_serv(p text) returns smallint language sql as $$
  select id from public.servicio where tipo = p::public.tipo_servicio $$;
-- Punto a `p_norte_m` metros al norte de una base en Bogotá.
create function public.p4t_punto(p_norte_m double precision) returns extensions.geography language sql as $$
  select extensions.st_setsrid(extensions.st_makepoint(-74.07, 4.65 + p_norte_m / 111320.0), 4326)::extensions.geography $$;
create function public.p4t_reporte(p_id uuid, p_servicio text, p_municipio text, p_norte_m double precision,
                                   p_creado timestamptz default now()) returns uuid language sql as $$
  insert into public.reporte (id, client_request_id, ciudadano_id, servicio_id, municipio_codigo, ubicacion, creado_en)
  values (p_id, gen_random_uuid(), 'c4444444-4444-4444-4444-444444444444', public.p4t_serv(p_servicio),
          p_municipio, public.p4t_punto(p_norte_m), p_creado)
  returning (select incidente_id from public.reporte where id = p_id) $$;
create function public.p4t_inc(p_reporte uuid) returns uuid language sql as $$
  select incidente_id from public.reporte where id = p_reporte $$;

-- ---------- datos ----------
insert into auth.users (id) values
  ('c4444444-4444-4444-4444-444444444444'),   -- ciudadano
  ('a4444444-4444-4444-4444-444444444444'),   -- operador de la empresa demo de energía
  ('d4444444-4444-4444-4444-444444444444');   -- admin
select public.promover_usuario('a4444444-4444-4444-4444-444444444444'::uuid, 'operador',
  (select id from empresa where nit = 'DEMO-0001'), 'Operador P4', 'Analista');
select public.promover_usuario('d4444444-4444-4444-4444-444444444444'::uuid, 'admin');

-- Aseo en Bogotá: dos empresas de prueba (cobertura ambigua).
insert into empresa (id, nombre, nit, tipo_entidad) values
  ('e4444444-0000-0000-0000-000000000001', 'Aseo P4 Uno', 'P4-ASEO-1', 'Empresa de servicios publicos'),
  ('e4444444-0000-0000-0000-000000000002', 'Aseo P4 Dos', 'P4-ASEO-2', 'Empresa de servicios publicos');
insert into empresa_cobertura (empresa_id, servicio_id, municipio_codigo) values
  ('e4444444-0000-0000-0000-000000000001', public.p4t_serv('aseo'), '11001'),
  ('e4444444-0000-0000-0000-000000000002', public.p4t_serv('aseo'), '11001');

-- ---------- configuración ----------
select is((select count(*)::int from config_agrupacion), 5, 'hay configuración para los 5 tipos de servicio');
select is((select radio_m from config_agrupacion where servicio_tipo = 'energia'), 1000, 'energía agrupa a 1000 m');

-- ---------- 1. primer reporte: crea incidente ----------
select public.p4t_reporte('14000000-0000-0000-0000-000000000001', 'energia', '11001', 0);
select isnt(public.p4t_inc('14000000-0000-0000-0000-000000000001'), null, 'el primer reporte crea un incidente');
select is((select estado::text from reporte where id = '14000000-0000-0000-0000-000000000001'), 'vinculado',
  'el reporte agrupado queda en estado vinculado');
select is((select empresa_id from incidente where id = public.p4t_inc('14000000-0000-0000-0000-000000000001')),
  (select id from empresa where nit = 'DEMO-0001'), 'el incidente toma la única empresa que cubre servicio y municipio');
select is((select estado::text from incidente where id = public.p4t_inc('14000000-0000-0000-0000-000000000001')),
  'recibido', 'el incidente nuevo nace en recibido');

-- ---------- 2. reporte cercano: mismo incidente y centroide recalculado ----------
select public.p4t_reporte('14000000-0000-0000-0000-000000000002', 'energia', '11001', 400);
select is(public.p4t_inc('14000000-0000-0000-0000-000000000002'), public.p4t_inc('14000000-0000-0000-0000-000000000001'),
  'un reporte a 400 m se suma al mismo incidente');
select ok(abs(extensions.st_distance(
    (select centroide from incidente where id = public.p4t_inc('14000000-0000-0000-0000-000000000001')),
    public.p4t_punto(200)) ) < 5,
  'el centroide queda en el punto medio de los reportes');

-- ---------- 3. lejos, otro municipio, otro servicio: incidentes nuevos ----------
select public.p4t_reporte('14000000-0000-0000-0000-000000000003', 'energia', '11001', 3000);
select isnt(public.p4t_inc('14000000-0000-0000-0000-000000000003'), public.p4t_inc('14000000-0000-0000-0000-000000000001'),
  'un reporte a 3 km crea otro incidente');
select public.p4t_reporte('14000000-0000-0000-0000-000000000004', 'energia', '25754', 0);
select isnt(public.p4t_inc('14000000-0000-0000-0000-000000000004'), public.p4t_inc('14000000-0000-0000-0000-000000000001'),
  'el mismo punto en otro municipio crea otro incidente');
select public.p4t_reporte('14000000-0000-0000-0000-000000000005', 'acueducto', '11001', 0);
select isnt(public.p4t_inc('14000000-0000-0000-0000-000000000005'), public.p4t_inc('14000000-0000-0000-0000-000000000001'),
  'otro servicio en el mismo punto crea otro incidente');

-- ---------- 4. fuera de la ventana de tiempo ----------
select public.p4t_reporte('14000000-0000-0000-0000-000000000006', 'energia', '11001', 0, now() + interval '7 hours');
select isnt(public.p4t_inc('14000000-0000-0000-0000-000000000006'), public.p4t_inc('14000000-0000-0000-0000-000000000001'),
  'un reporte 7 h después de la última actividad crea otro incidente');

-- ---------- 5. estados del incidente ----------
update incidente set estado = 'en_atencion' where id = public.p4t_inc('14000000-0000-0000-0000-000000000005');
select public.p4t_reporte('14000000-0000-0000-0000-000000000007', 'acueducto', '11001', 100);
select is(public.p4t_inc('14000000-0000-0000-0000-000000000007'), public.p4t_inc('14000000-0000-0000-0000-000000000005'),
  'se agrupa en un incidente en_atencion');
update incidente set estado = 'cerrado' where id = public.p4t_inc('14000000-0000-0000-0000-000000000003');
select public.p4t_reporte('14000000-0000-0000-0000-000000000008', 'energia', '11001', 3050);
select isnt(public.p4t_inc('14000000-0000-0000-0000-000000000008'), public.p4t_inc('14000000-0000-0000-0000-000000000003'),
  'no se agrupa en un incidente cerrado');

-- ---------- 6. cobertura ambigua o inexistente ----------
select public.p4t_reporte('14000000-0000-0000-0000-000000000009', 'aseo', '11001', 0);
select is((select empresa_id from incidente where id = public.p4t_inc('14000000-0000-0000-0000-000000000009')), null,
  'con dos empresas para el mismo servicio y municipio el incidente queda sin empresa');
select public.p4t_reporte('14000000-0000-0000-0000-000000000010', 'alcantarillado', '11001', 0);
select is((select empresa_id from incidente where id = public.p4t_inc('14000000-0000-0000-0000-000000000010')), null,
  'sin cobertura el incidente queda sin empresa');

-- ---------- 7. reportes que ya llegan vinculados no se tocan ----------
insert into reporte (id, client_request_id, ciudadano_id, servicio_id, municipio_codigo, ubicacion, estado, incidente_id)
values ('14000000-0000-0000-0000-000000000011', gen_random_uuid(), 'c4444444-4444-4444-4444-444444444444',
        public.p4t_serv('energia'), '11001', public.p4t_punto(0), 'vinculado',
        public.p4t_inc('14000000-0000-0000-0000-000000000003'));
select is(public.p4t_inc('14000000-0000-0000-0000-000000000011'), public.p4t_inc('14000000-0000-0000-0000-000000000003'),
  'un reporte que ya trae incidente conserva el suyo');

-- ---------- 8. trazabilidad: outbox y auditoría ----------
select ok(exists (select 1 from evento_outbox
  where tipo = 'reporte.estado_cambiado'
    and payload ->> 'reporte_id' = '14000000-0000-0000-0000-000000000002'
    and payload ->> 'incidente_id' = public.p4t_inc('14000000-0000-0000-0000-000000000002')::text),
  'la vinculación emite reporte.estado_cambiado con el incidente');
select ok(exists (select 1 from audit_log
  where entidad = 'incidente' and entidad_id = public.p4t_inc('14000000-0000-0000-0000-000000000001')),
  'la creación del incidente queda auditada');

-- ---------- 9. flujo real: registrar_reporte como ciudadano ----------
select public.p4t_como('c4444444-4444-4444-4444-444444444444');
-- En otra sentencia: la misma sentencia no vería la fila que inserta la función.
select set_config('p4t.rid', (select reporte_id::text from public.registrar_reporte(
  gen_random_uuid(), public.p4t_serv('energia'), '11001', 4.65 + 300 / 111320.0, -74.07)), true);
select is((select incidente_id from reporte where id = current_setting('p4t.rid')::uuid),
  public.p4t_inc('14000000-0000-0000-0000-000000000001'),
  'un reporte del ciudadano por registrar_reporte se agrupa automáticamente');

-- ---------- 10. incidentes_cercanos ----------
select is((select incidente_id from public.incidentes_cercanos(public.p4t_serv('energia'), 4.65 + 250 / 111320.0, -74.07) limit 1),
  public.p4t_inc('14000000-0000-0000-0000-000000000001'), 'incidentes_cercanos devuelve el incidente más cercano');
select is((select count(*)::int from public.incidentes_cercanos(public.p4t_serv('energia'), 6.0, -75.0)), 0,
  'incidentes_cercanos no devuelve nada lejos');
select is((select count(*)::int from public.incidentes_cercanos(public.p4t_serv('energia'), 99, -74.07)), 0,
  'incidentes_cercanos ignora coordenadas fuera de rango');

-- ---------- 11. permisos ----------
select throws_ok($$select private.agrupar_reporte()$$, '42501', null, 'un cliente no puede ejecutar la función interna');
update config_agrupacion set radio_m = 50 where servicio_tipo = 'energia';
reset role;
select is((select radio_m from config_agrupacion where servicio_tipo = 'energia'), 1000, 'un ciudadano no cambia la configuración');

select public.p4t_como('a4444444-4444-4444-4444-444444444444');
update config_agrupacion set radio_m = 50 where servicio_tipo = 'energia';
reset role;
select is((select radio_m from config_agrupacion where servicio_tipo = 'energia'), 1000, 'un operador no cambia la configuración');

select public.p4t_como('d4444444-4444-4444-4444-444444444444');
update config_agrupacion set radio_m = 800 where servicio_tipo = 'energia';
reset role;
select is((select radio_m from config_agrupacion where servicio_tipo = 'energia'), 800, 'el admin sí cambia la configuración');

select * from finish();
rollback;
