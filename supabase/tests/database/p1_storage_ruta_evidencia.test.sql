begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

create function public.t_como(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.headers', '{"x-forwarded-for":"192.0.2.30"}', true);
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

-- C1 y C2: ciudadanos. A1: operador de la empresa A, que cubre energía en Bogotá.
insert into auth.users (id) values
  ('c1111111-1111-1111-1111-111111111111'),
  ('c2222222-2222-2222-2222-222222222222'),
  ('a1111111-1111-1111-1111-111111111111');

insert into empresa (id, nombre, nit, tipo_entidad)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Empresa Test A', 'TEST-A', 'Empresa de servicios publicos');
insert into empresa_cobertura (empresa_id, servicio_id, municipio_codigo)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', public.t_serv('energia'), '11001');
select public.promover_usuario('a1111111-1111-1111-1111-111111111111'::uuid, 'operador',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, 'Operador A1', 'Analista');

-- Dos fotos de C2: una ligada a su reporte y una sin reporte
insert into storage.objects (bucket_id, name) values
  ('evidencias-reportes', 'c2222222-2222-2222-2222-222222222222/privada.jpg'),
  ('evidencias-reportes', 'c2222222-2222-2222-2222-222222222222/huerfana.jpg');
insert into reporte (id, client_request_id, ciudadano_id, servicio_id, municipio_codigo, ubicacion, url_evidencia)
values ('10000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000002',
        'c2222222-2222-2222-2222-222222222222', public.t_serv('energia'), '11001', public.t_punto(),
        'c2222222-2222-2222-2222-222222222222/privada.jpg');

select ok(exists (select 1 from pg_constraint where conname = 'reporte_evidencia_en_carpeta_propia'),
  'existe la restricción de ruta de evidencia');

-- ---------- C1 intenta apuntar a la foto de C2 ----------
select public.t_como('c1111111-1111-1111-1111-111111111111');

select is(public.t_dml($$select * from public.registrar_reporte(
  '40000000-0000-0000-0000-000000000011', public.t_serv('energia'), '11001', 4.65, -74.07,
  'Intento de robar foto', 'c2222222-2222-2222-2222-222222222222/privada.jpg')$$),
  'error:23514', 'registrar_reporte rechaza una ruta de evidencia ajena');

select is(public.t_dml($$insert into public.reporte (client_request_id, ciudadano_id, servicio_id, municipio_codigo, ubicacion, url_evidencia)
  values ('40000000-0000-0000-0000-000000000012', 'c1111111-1111-1111-1111-111111111111',
  public.t_serv('energia'), '11001', public.t_punto(), 'c2222222-2222-2222-2222-222222222222/privada.jpg')$$),
  'error:23514', 'el INSERT directo rechaza una ruta de evidencia ajena');

select is(public.t_filas($$select 1 from storage.objects where name = 'c2222222-2222-2222-2222-222222222222/privada.jpg'$$),
  0::bigint, 'C1 no lee la foto de C2');

select is(public.t_dml($$select * from public.registrar_reporte(
  '40000000-0000-0000-0000-000000000013', public.t_serv('energia'), '11001', 4.65, -74.07,
  'Reporte con foto propia', 'c1111111-1111-1111-1111-111111111111/mia.jpg')$$),
  'ok:1', 'un reporte con ruta en su propia carpeta sí se acepta');

select is(public.t_dml($$select * from public.registrar_reporte(
  '40000000-0000-0000-0000-000000000014', public.t_serv('energia'), '11001', 4.65, -74.07,
  'Reporte sin foto')$$),
  'ok:1', 'un reporte sin foto sigue funcionando');

-- ---------- C2 ----------
reset role;
select public.t_como('c2222222-2222-2222-2222-222222222222');
select is(public.t_filas($$select 1 from storage.objects where name like 'c2222222-2222-2222-2222-222222222222/%'$$),
  2::bigint, 'C2 lee sus dos fotos');

-- ---------- operador que cubre el reporte ----------
reset role;
select public.t_como('a1111111-1111-1111-1111-111111111111');
select is(public.t_filas($$select 1 from storage.objects where name = 'c2222222-2222-2222-2222-222222222222/privada.jpg'$$),
  1::bigint, 'el operador lee la foto de un reporte que cubre');
select is(public.t_filas($$select 1 from storage.objects where name = 'c2222222-2222-2222-2222-222222222222/huerfana.jpg'$$),
  0::bigint, 'el operador no lee fotos sin reporte asociado');

reset role;
select * from finish();
rollback;