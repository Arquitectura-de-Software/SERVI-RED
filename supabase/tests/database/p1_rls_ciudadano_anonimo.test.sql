begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- ---------- ayudantes (se deshacen al final) ----------
create function public.t_como(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.headers', '{"x-forwarded-for":"192.0.2.11"}', true);
  set local role authenticated;
end $$;
create function public.t_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.headers', '{"x-forwarded-for":"192.0.2.10"}', true);
  set local role anon;
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
insert into auth.users (id) values
  ('c1111111-1111-1111-1111-111111111111'),
  ('c2222222-2222-2222-2222-222222222222');

insert into reporte (id, client_request_id, ciudadano_id, servicio_id, municipio_codigo, ubicacion)
values ('10000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000002',
        'c2222222-2222-2222-2222-222222222222', public.t_serv('energia'), '11001', public.t_punto());

insert into incidente (id, servicio_id, municipio_codigo)
values ('20000000-0000-0000-0000-000000000001', public.t_serv('energia'), '11001');

-- ---------- perfiles automáticos ----------
select is((select rol::text from perfil where id = 'c1111111-1111-1111-1111-111111111111'),
  'ciudadano', 'el trigger crea el perfil como ciudadano');
select is((select nombre_anonimo from ciudadano where id = 'c1111111-1111-1111-1111-111111111111'),
  'Ciudadano-c1111111', 'el ciudadano recibe un alias anónimo');

-- ---------- ciudadano 1 (sesión anónima) ----------
select public.t_como('c1111111-1111-1111-1111-111111111111');

select is(public.t_dml($$insert into public.reporte (id, client_request_id, ciudadano_id, servicio_id, municipio_codigo, ubicacion)
  values ('10000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001',
  'c1111111-1111-1111-1111-111111111111', public.t_serv('energia'), '11001', public.t_punto())$$),
  'ok:1', 'ciudadano crea un reporte propio');

select is(public.t_dml($$insert into public.reporte (id, client_request_id, ciudadano_id, servicio_id, municipio_codigo, ubicacion)
  values ('10000000-0000-0000-0000-000000000004', '40000000-0000-0000-0000-000000000004',
  'c2222222-2222-2222-2222-222222222222', public.t_serv('energia'), '11001', public.t_punto())$$),
  'error:42501', 'no puede crear reportes a nombre de otro');

select is(public.t_dml($$insert into public.reporte (id, client_request_id, ciudadano_id, servicio_id, municipio_codigo, ubicacion, estado)
  values ('10000000-0000-0000-0000-000000000005', '40000000-0000-0000-0000-000000000005',
  'c1111111-1111-1111-1111-111111111111', public.t_serv('energia'), '11001', public.t_punto(), 'vinculado')$$),
  'error:42501', 'no puede crear un reporte ya vinculado');

select is(public.t_dml($$insert into public.reporte (id, client_request_id, ciudadano_id, servicio_id, municipio_codigo, ubicacion, incidente_id)
  values ('10000000-0000-0000-0000-000000000006', '40000000-0000-0000-0000-000000000006',
  'c1111111-1111-1111-1111-111111111111', public.t_serv('energia'), '11001', public.t_punto(),
  '20000000-0000-0000-0000-000000000001')$$),
  'error:42501', 'no puede asignarse un incidente al crear el reporte');

select is(public.t_dml($$insert into public.reporte (id, client_request_id, ciudadano_id, servicio_id, municipio_codigo, ubicacion)
  values ('10000000-0000-0000-0000-000000000007', '40000000-0000-0000-0000-000000000001',
  'c1111111-1111-1111-1111-111111111111', public.t_serv('energia'), '11001', public.t_punto())$$),
  'error:23505', 'repetir client_request_id no duplica el reporte');

select is(public.t_filas($$select 1 from public.reporte where id = '10000000-0000-0000-0000-000000000001'$$),
  1::bigint, 've su propio reporte');
select is(public.t_filas($$select 1 from public.reporte where id = '10000000-0000-0000-0000-000000000002'$$),
  0::bigint, 'no ve el reporte de otro ciudadano');
select is(public.t_dml($$update public.reporte set estado = 'descartado' where id = '10000000-0000-0000-0000-000000000001'$$),
  'ok:0', 'no puede cambiar el estado de su reporte');

select is(public.t_filas($$select 1 from public.incidente where id = '20000000-0000-0000-0000-000000000001'$$),
  1::bigint, 'cualquier sesión ve los incidentes');
select is(public.t_dml($$insert into public.incidente (servicio_id, municipio_codigo) values (public.t_serv('energia'), '11001')$$),
  'error:42501', 'ciudadano no crea incidentes');

select is(public.t_dml($$insert into public.confirmacion_ciudadana (incidente_id, ciudadano_id, tipo)
  values ('20000000-0000-0000-0000-000000000001', 'c1111111-1111-1111-1111-111111111111', 'restablecido')$$),
  'ok:1', 'ciudadano confirma a su nombre');
select is(public.t_dml($$insert into public.confirmacion_ciudadana (incidente_id, ciudadano_id, tipo)
  values ('20000000-0000-0000-0000-000000000001', 'c2222222-2222-2222-2222-222222222222', 'sin_servicio')$$),
  'error:42501', 'no confirma a nombre de otro');

select is(public.t_filas($$select 1 from public.perfil$$), 1::bigint, 'solo ve su propio perfil');
select is(public.t_dml($$update public.perfil set rol = 'admin' where id = 'c1111111-1111-1111-1111-111111111111'$$),
  'ok:0', 'no puede cambiarse el rol');
select is(public.t_dml($$insert into public.perfil (id, rol) values (gen_random_uuid(), 'admin')$$),
  'error:42501', 'no puede insertar perfiles');
select is(public.t_dml($$select public.promover_usuario('c1111111-1111-1111-1111-111111111111'::uuid, 'admin')$$),
  'error:42501', 'no puede ejecutar promover_usuario');

select is(public.t_filas($$select 1 from public.audit_log$$), 0::bigint, 'no lee audit_log');
select is(public.t_filas($$select 1 from public.evento_outbox$$), 0::bigint, 'no lee evento_outbox');
select is(public.t_filas($$select 1 from public.indicador$$), 0::bigint, 'no lee indicadores');
select is(public.t_filas($$select 1 from public.denuncia$$), 0::bigint, 'no lee denuncias');
select is(public.t_dml($$insert into public.denuncia (client_request_id, servicio_id, descripcion, seguimiento_hash)
  values (gen_random_uuid(), public.t_serv('energia'), 'Descripcion larga de prueba', 'hash-x')$$),
  'error:42501', 'no inserta denuncias directamente');

-- ---------- sin sesión (anon) ----------
reset role;
select public.t_anon();

select ok(public.t_filas($$select 1 from public.departamento$$) > 0, 'sin sesión lee catálogos');
select is(public.t_filas($$select 1 from public.reporte$$), 0::bigint, 'sin sesión no ve reportes');
select is(public.t_filas($$select 1 from public.incidente$$), 0::bigint, 'sin sesión no ve incidentes');
select is(public.t_dml($$insert into public.reporte (client_request_id, servicio_id, municipio_codigo, ubicacion)
  values (gen_random_uuid(), public.t_serv('energia'), '11001', public.t_punto())$$),
  'error:42501', 'sin sesión no crea reportes');

select is(public.t_dml($$select public.registrar_denuncia('41000000-0000-0000-0000-000000000001'::uuid,
  public.t_serv('energia'), '11001', 'Posible conexion fraudulenta de prueba', 'codigo-seguimiento-1234567890',
  4.6512, -74.0723, null)$$),
  'ok:1', 'sin sesión se registra una denuncia');

select is(
  public.registrar_denuncia('41000000-0000-0000-0000-000000000001'::uuid, public.t_serv('energia'), '11001',
    'Posible conexion fraudulenta de prueba', 'codigo-seguimiento-1234567890'),
  public.registrar_denuncia('41000000-0000-0000-0000-000000000001'::uuid, public.t_serv('energia'), '11001',
    'Posible conexion fraudulenta de prueba', 'codigo-seguimiento-1234567890'),
  'reintentar con el mismo client_request_id devuelve la misma denuncia');

select is(public.t_dml($$select public.registrar_denuncia('41000000-0000-0000-0000-000000000002'::uuid,
  public.t_serv('energia'), '11001', 'Descripcion suficientemente larga', 'corto')$$),
  'error:PT400', 'rechaza códigos de seguimiento cortos');
select is(public.t_dml($$select public.registrar_denuncia('41000000-0000-0000-0000-000000000003'::uuid,
  public.t_serv('energia'), null, 'Descripcion suficientemente larga', 'codigo-seguimiento-1234567890')$$),
  'error:PT400', 'rechaza denuncias sin municipio');
select is(public.t_dml($$select public.registrar_denuncia('41000000-0000-0000-0000-000000000004'::uuid,
  public.t_serv('energia'), '11001', 'Descripcion suficientemente larga', 'codigo-seguimiento-1234567890', 95, -74)$$),
  'error:PT400', 'rechaza coordenadas fuera de rango');

select is(public.t_filas($$select * from public.consultar_denuncia('codigo-seguimiento-1234567890')$$),
  1::bigint, 'el código correcto devuelve la denuncia');
select is((select estado::text from public.consultar_denuncia('codigo-seguimiento-1234567890')),
  'recibida', 'el denunciante ve el estado');
select is(public.t_filas($$select * from public.consultar_denuncia('codigo-equivocado-1234567890')$$),
  0::bigint, 'un código equivocado no devuelve nada');
select is(public.t_filas($$select * from public.consultar_denuncia('corto')$$),
  0::bigint, 'un código corto no devuelve nada');

-- ---------- comprobaciones como administrador de la base ----------
reset role;

select is((select count(*) from denuncia where client_request_id = '41000000-0000-0000-0000-000000000001'),
  1::bigint, 'solo existe una denuncia por client_request_id');
select is((select seguimiento_hash from denuncia where client_request_id = '41000000-0000-0000-0000-000000000001'),
  encode(extensions.digest('codigo-seguimiento-1234567890', 'sha256'), 'hex'),
  'se guarda el hash SHA-256, no el código');
select columns_are('public', 'denuncia',
  array['id','client_request_id','servicio_id','municipio_codigo','ubicacion_aprox','descripcion',
        'url_evidencia','estado','seguimiento_hash','creada_en'],
  'denuncia no tiene columnas que identifiquen al denunciante');
select is((select rol::text from perfil where id = 'c1111111-1111-1111-1111-111111111111'),
  'ciudadano', 'el rol del ciudadano sigue siendo ciudadano');

select * from finish();
rollback;