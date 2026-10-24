begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- ---------- ayudantes ----------
create function public.t_como(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.headers', '{"x-forwarded-for":"192.0.2.13"}', true);
  set local role authenticated;
end $$;
create function public.t_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  set local role anon;
end $$;
create function public.t_servidor() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  set local role service_role;
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
-- C1, C2: ciudadanos. A1: operador de A. B1: operador de B. E1: regulador. F1: admin. D1: para probar service_role.
insert into auth.users (id) values
  ('c1111111-1111-1111-1111-111111111111'),
  ('c2222222-2222-2222-2222-222222222222'),
  ('a1111111-1111-1111-1111-111111111111'),
  ('b1111111-1111-1111-1111-111111111111'),
  ('e1111111-1111-1111-1111-111111111111'),
  ('f1111111-1111-1111-1111-111111111111'),
  ('d1111111-1111-1111-1111-111111111111');

insert into empresa (id, nombre, nit, tipo_entidad) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Empresa Test A', 'TEST-A', 'Empresa de servicios publicos'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Empresa Test B', 'TEST-B', 'Empresa de servicios publicos');
insert into empresa_cobertura (empresa_id, servicio_id, municipio_codigo) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', public.t_serv('energia'), '11001'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', public.t_serv('energia'), '05001');

select public.promover_usuario('a1111111-1111-1111-1111-111111111111'::uuid, 'operador', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, 'Operador A1', 'Analista');
select public.promover_usuario('b1111111-1111-1111-1111-111111111111'::uuid, 'operador', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid, 'Operador B1', 'Analista');
select public.promover_usuario('e1111111-1111-1111-1111-111111111111'::uuid, 'regulador');
select public.promover_usuario('f1111111-1111-1111-1111-111111111111'::uuid, 'admin');

insert into reporte (id, client_request_id, ciudadano_id, servicio_id, municipio_codigo, ubicacion, url_evidencia)
values ('10000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001',
        'c1111111-1111-1111-1111-111111111111', public.t_serv('energia'), '11001', public.t_punto(),
        'c1111111-1111-1111-1111-111111111111/cubierta.jpg');

insert into incidente (id, servicio_id, empresa_id, municipio_codigo)
values ('20000000-0000-0000-0000-000000000001', public.t_serv('energia'), 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11001');

insert into denuncia (id, client_request_id, servicio_id, municipio_codigo, descripcion, seguimiento_hash, url_evidencia)
values ('30000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000002',
        public.t_serv('energia'), '11001', 'Descripcion de prueba D1', 'HASH-SECRETO-TEST', 'denuncia-foto-1.jpg');

insert into indicador (id, tipo, valor, periodo_inicio, periodo_fin)
values ('60000000-0000-0000-0000-000000000001', 'pgtap-continuidad', 99.5, current_date, current_date);

insert into storage.objects (bucket_id, name) values
  ('evidencias-reportes',  'c1111111-1111-1111-1111-111111111111/cubierta.jpg'),
  ('evidencias-reportes',  'c1111111-1111-1111-1111-111111111111/huerfana.jpg'),
  ('evidencias-denuncias', 'denuncia-foto-1.jpg');

-- ---------- buckets ----------
select is((select b.public from storage.buckets b where b.id = 'evidencias-reportes'), false, 'bucket de reportes es privado');
select is((select b.public from storage.buckets b where b.id = 'evidencias-denuncias'), false, 'bucket de denuncias es privado');
select is((select b.file_size_limit from storage.buckets b where b.id = 'evidencias-reportes'), 5242880::bigint, 'límite de 5 MB en reportes');
select is((select b.allowed_mime_types from storage.buckets b where b.id = 'evidencias-denuncias'),
  array['image/jpeg','image/png','image/webp'], 'solo imágenes JPEG, PNG y WebP');

-- ---------- triggers de auditoría ----------
select has_trigger('public', 'incidente',  'aud_incidente',  'auditoría de incidente');
select has_trigger('public', 'validacion', 'aud_validacion', 'auditoría de validacion');
select has_trigger('public', 'respuesta',  'aud_respuesta',  'auditoría de respuesta');
select has_trigger('public', 'reporte',    'aud_reporte',    'auditoría de reporte');
select has_trigger('public', 'denuncia',   'aud_denuncia',   'auditoría de denuncia');

-- ---------- regulador ----------
select public.t_como('e1111111-1111-1111-1111-111111111111');
select is(public.t_filas($$select 1 from public.indicador where id = '60000000-0000-0000-0000-000000000001'$$), 1::bigint, 'el regulador lee indicadores');
select is(public.t_dml($$insert into public.indicador (tipo, valor, periodo_inicio, periodo_fin) values ('x', 1, current_date, current_date)$$), 'error:42501', 'el regulador no escribe indicadores');
select is(public.t_filas($$select 1 from public.reporte where id = '10000000-0000-0000-0000-000000000001'$$), 0::bigint, 'el regulador no ve reportes individuales');
select is(public.t_filas($$select 1 from public.denuncia where id = '30000000-0000-0000-0000-000000000001'$$), 0::bigint, 'el regulador no ve denuncias');
select is(public.t_filas($$select 1 from public.incidente where id = '20000000-0000-0000-0000-000000000001'$$), 1::bigint, 'el regulador ve incidentes');
select is(public.t_dml($$update public.incidente set prioridad = 1 where id = '20000000-0000-0000-0000-000000000001'$$), 'ok:0', 'el regulador no gestiona incidentes');
select is(public.t_filas($$select 1 from public.audit_log$$), 0::bigint, 'el regulador no lee audit_log');
select is(public.t_filas($$select 1 from public.evento_outbox$$), 0::bigint, 'el regulador no lee evento_outbox');

-- ---------- operador y ciudadano frente a lo restringido ----------
reset role;
select public.t_como('a1111111-1111-1111-1111-111111111111');
select is(public.t_filas($$select 1 from public.indicador where id = '60000000-0000-0000-0000-000000000001'$$), 1::bigint, 'el operador lee indicadores');
select is(public.t_filas($$select 1 from public.audit_log$$), 0::bigint, 'el operador no lee audit_log');
select is(public.t_dml($$insert into public.evento_outbox (tipo) values ('x')$$), 'error:42501', 'el operador no escribe en evento_outbox');
select is(public.t_dml($$select public.promover_usuario('a1111111-1111-1111-1111-111111111111'::uuid, 'admin')$$), 'error:42501', 'el operador no ejecuta promover_usuario');

reset role;
select public.t_como('c1111111-1111-1111-1111-111111111111');
select is(public.t_filas($$select 1 from public.indicador where id = '60000000-0000-0000-0000-000000000001'$$), 0::bigint, 'el ciudadano no lee indicadores');

reset role;
select public.t_anon();
select is(public.t_filas($$select 1 from public.indicador where id = '60000000-0000-0000-0000-000000000001'$$), 0::bigint, 'sin sesión no se leen indicadores');

-- ---------- administrador ----------
reset role;
select public.t_como('f1111111-1111-1111-1111-111111111111');
select is(public.t_filas($$select 1 from public.reporte where id = '10000000-0000-0000-0000-000000000001'$$), 1::bigint, 'admin ve reportes');
select is(public.t_filas($$select 1 from public.denuncia where id = '30000000-0000-0000-0000-000000000001'$$), 1::bigint, 'admin ve denuncias');
select is(public.t_filas($$select 1 from public.indicador where id = '60000000-0000-0000-0000-000000000001'$$), 1::bigint, 'admin lee indicadores');
select is(public.t_filas($$select 1 from public.perfil where id in ('c1111111-1111-1111-1111-111111111111','a1111111-1111-1111-1111-111111111111','b1111111-1111-1111-1111-111111111111')$$), 3::bigint, 'admin ve todos los perfiles');
select is(public.t_dml($$update public.incidente set prioridad = 2 where id = '20000000-0000-0000-0000-000000000001'$$), 'ok:1', 'admin gestiona incidentes');
select is(public.t_dml($$update public.denuncia set estado = 'validada' where id = '30000000-0000-0000-0000-000000000001'$$), 'ok:1', 'admin cambia el estado de una denuncia');
select is(public.t_dml($$update public.denuncia set seguimiento_hash = 'otro' where id = '30000000-0000-0000-0000-000000000001'$$), 'error:42501', 'nadie edita el hash de seguimiento');
select ok(public.t_filas($$select 1 from public.audit_log where entidad_id = '20000000-0000-0000-0000-000000000001'$$) >= 1, 'admin lee audit_log');
select is(public.t_dml($$insert into public.audit_log (accion, entidad) values ('x', 'x')$$), 'error:42501', 'nadie escribe audit_log desde el cliente');
select is(public.t_filas($$select 1 from public.evento_outbox$$), 0::bigint, 'ni admin lee evento_outbox desde el cliente');
select is(public.t_dml($$select public.promover_usuario('c1111111-1111-1111-1111-111111111111'::uuid, 'admin')$$), 'error:42501', 'admin no ejecuta promover_usuario desde el cliente');

-- ---------- promover_usuario como servidor ----------
reset role;
select public.t_servidor();
select is(public.t_dml($$select public.promover_usuario('d1111111-1111-1111-1111-111111111111'::uuid, 'regulador')$$), 'ok:1', 'service_role sí ejecuta promover_usuario');

-- ---------- auditoría (como administrador de la base) ----------
reset role;
select is((select rol::text from perfil where id = 'd1111111-1111-1111-1111-111111111111'), 'regulador', 'promover_usuario cambió el rol');
select ok((select count(*) from audit_log where entidad = 'incidente' and entidad_id = '20000000-0000-0000-0000-000000000001'
  and accion = 'update' and actor_id = 'f1111111-1111-1111-1111-111111111111') >= 1, 'la auditoría registra al actor de un cambio de incidente');
select ok((select count(*) from audit_log where entidad = 'denuncia' and entidad_id = '30000000-0000-0000-0000-000000000001'
  and accion = 'update') >= 1, 'la auditoría registra cambios de denuncia');
select is((select count(*) from audit_log where entidad = 'denuncia' and entidad_id = '30000000-0000-0000-0000-000000000001'
  and (coalesce(antes::text, '') like '%seguimiento_hash%' or coalesce(despues::text, '') like '%seguimiento_hash%'
       or coalesce(antes::text, '') like '%HASH-SECRETO-TEST%' or coalesce(despues::text, '') like '%HASH-SECRETO-TEST%')),
  0::bigint, 'la auditoría nunca guarda el hash de seguimiento');

-- ---------- Storage: subir ----------
select public.t_como('c1111111-1111-1111-1111-111111111111');
select is(public.t_dml($$insert into storage.objects (bucket_id, name) values ('evidencias-reportes', 'c1111111-1111-1111-1111-111111111111/nueva.jpg')$$), 'ok:1', 'C1 sube a su carpeta');
select is(public.t_dml($$insert into storage.objects (bucket_id, name) values ('evidencias-reportes', 'c2222222-2222-2222-2222-222222222222/x.jpg')$$), 'error:42501', 'C1 no sube a la carpeta de otro');
select is(public.t_dml($$insert into storage.objects (bucket_id, name) values ('evidencias-reportes', 'raiz.jpg')$$), 'error:42501', 'no se sube sin carpeta propia');
select is(public.t_dml($$insert into storage.objects (bucket_id, name) values ('evidencias-denuncias', 'aleatorio-1.jpg')$$), 'ok:1', 'una sesión sube foto de denuncia con nombre plano');
select is(public.t_dml($$insert into storage.objects (bucket_id, name) values ('evidencias-denuncias', 'carpeta/x.jpg')$$), 'error:42501', 'la foto de denuncia no admite carpetas');

-- ---------- Storage: leer ----------
select is(public.t_filas($$select 1 from storage.objects where bucket_id = 'evidencias-reportes' and name = 'c1111111-1111-1111-1111-111111111111/huerfana.jpg'$$), 1::bigint, 'el autor lee sus fotos');
select is(public.t_filas($$select 1 from storage.objects where bucket_id = 'evidencias-denuncias' and name = 'aleatorio-1.jpg'$$), 0::bigint, 'quien sube una foto de denuncia no la puede leer');
select is(public.t_filas($$select 1 from storage.objects where bucket_id = 'evidencias-denuncias' and name = 'denuncia-foto-1.jpg'$$), 0::bigint, 'un ciudadano no lee fotos de denuncias');

reset role;
select public.t_como('c2222222-2222-2222-2222-222222222222');
select is(public.t_filas($$select 1 from storage.objects where bucket_id = 'evidencias-reportes' and name = 'c1111111-1111-1111-1111-111111111111/cubierta.jpg'$$), 0::bigint, 'C2 no lee fotos de C1');

reset role;
select public.t_anon();
select is(public.t_dml($$insert into storage.objects (bucket_id, name) values ('evidencias-denuncias', 'anon-1.jpg')$$), 'error:42501', 'sin ninguna sesión no se sube nada');

reset role;
select public.t_como('a1111111-1111-1111-1111-111111111111');
select is(public.t_filas($$select 1 from storage.objects where bucket_id = 'evidencias-reportes' and name = 'c1111111-1111-1111-1111-111111111111/cubierta.jpg'$$), 1::bigint, 'el operador lee la foto de un reporte que cubre');
select is(public.t_filas($$select 1 from storage.objects where bucket_id = 'evidencias-reportes' and name = 'c1111111-1111-1111-1111-111111111111/huerfana.jpg'$$), 0::bigint, 'el operador no lee fotos sin reporte asociado');
select is(public.t_filas($$select 1 from storage.objects where bucket_id = 'evidencias-denuncias' and name = 'denuncia-foto-1.jpg'$$), 1::bigint, 'el operador lee la foto de una denuncia que cubre');

reset role;
select public.t_como('b1111111-1111-1111-1111-111111111111');
select is(public.t_filas($$select 1 from storage.objects where bucket_id = 'evidencias-reportes' and name = 'c1111111-1111-1111-1111-111111111111/cubierta.jpg'$$), 0::bigint, 'el operador de otra zona no lee esa foto');
select is(public.t_filas($$select 1 from storage.objects where bucket_id = 'evidencias-denuncias' and name = 'denuncia-foto-1.jpg'$$), 0::bigint, 'el operador de otra zona no lee la foto de la denuncia');

reset role;
select public.t_como('f1111111-1111-1111-1111-111111111111');
select is(public.t_filas($$select 1 from storage.objects where bucket_id = 'evidencias-reportes' and name = 'c1111111-1111-1111-1111-111111111111/huerfana.jpg'$$), 1::bigint, 'admin lee cualquier foto de reportes');
select is(public.t_filas($$select 1 from storage.objects where bucket_id = 'evidencias-denuncias' and name = 'denuncia-foto-1.jpg'$$), 1::bigint, 'admin lee fotos de denuncias');

reset role;
select * from finish();
rollback;