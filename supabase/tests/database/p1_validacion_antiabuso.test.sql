begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

create function public.t_como(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text,
    true
  );
  set local role authenticated;
end $$;
create function public.t_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.headers', '{"x-forwarded-for":"198.51.100.20"}', true);
  set local role anon;
end $$;
create function public.t_dml(p_sql text) returns text language plpgsql as $$
declare
  n bigint;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return 'ok:' || n;
exception when others then
  return 'error:' || sqlstate;
end $$;

insert into auth.users (id) values
  ('c1111111-1111-1111-1111-111111111111'),
  ('c2222222-2222-2222-2222-222222222222'),
  ('c3333333-3333-3333-3333-333333333333');

select set_config(
  'request.headers',
  '{"x-correlation-id":"70000000-0000-0000-0000-000000000001","x-forwarded-for":"203.0.113.99, 198.51.100.20"}',
  true
);
select is(private.ip_solicitante_actual()::text, '198.51.100.20/32',
  'la IP se toma del último salto agregado por el gateway, no de un valor inicial manipulable');
select public.t_como('c1111111-1111-1111-1111-111111111111');
select set_config('request.headers', '{"x-correlation-id":"not-a-uuid"}', true);
select is(public.t_dml($$select * from public.registrar_reporte(
  '40000000-0000-0000-0000-000000000009',
  (select id from public.servicio where tipo = 'energia'),
  '11001', 4.65, -74.07, 'ID de correlación inválido'
)$$), 'error:PT400', 'rechaza un correlation_id mal formado');
select set_config(
  'request.headers',
  '{"x-correlation-id":"70000000-0000-0000-0000-000000000001","x-forwarded-for":"203.0.113.99, 198.51.100.20"}',
  true
);

create temporary table primer_reporte on commit drop as
select * from public.registrar_reporte(
  '40000000-0000-0000-0000-000000000001',
  (select id from public.servicio where tipo = 'energia'),
  '11001', 4.65, -74.07, 'Interrupción del servicio'
);

select is((select correlation_id from primer_reporte),
  '70000000-0000-0000-0000-000000000001'::uuid,
  'el RPC devuelve el correlation_id recibido');
reset role;
select is((select correlation_id from public.evento_outbox where tipo = 'reporte.creado'),
  '70000000-0000-0000-0000-000000000001'::uuid,
  'el evento outbox conserva el correlation_id de la solicitud');
select public.t_como('c1111111-1111-1111-1111-111111111111');
select is((select count(*) from public.reporte), 1::bigint, 'el primer RPC crea un reporte');

create temporary table reintento_reporte on commit drop as
select * from public.registrar_reporte(
  '40000000-0000-0000-0000-000000000001',
  (select id from public.servicio where tipo = 'energia'),
  '11001', 4.65, -74.07, 'Interrupción del servicio'
);
select is((select reporte_id from reintento_reporte),
  (select reporte_id from primer_reporte),
  'repetir client_request_id devuelve el reporte original');
do $$
declare
  i integer;
begin
  for i in 1..10 loop
    perform * from public.registrar_reporte(
      '40000000-0000-0000-0000-000000000001',
      (select id from public.servicio where tipo = 'energia'),
      '11001', 4.65, -74.07, 'Reintento idempotente'
    );
  end loop;
end;
$$;
select ok(true, 'los reintentos idempotentes no consumen la cuota de creación');
select is((select count(*) from public.reporte), 1::bigint,
  'el reintento no duplica el reporte');
reset role;
select is((select count(*) from public.evento_outbox where tipo = 'reporte.creado'),
  1::bigint, 'el reintento no duplica el evento');

select public.t_como('c1111111-1111-1111-1111-111111111111');
select is(public.t_dml($$select * from public.registrar_reporte(
  '40000000-0000-0000-0000-000000000002',
  (select id from public.servicio where tipo = 'energia'),
  '11001', 91, -74.07, 'Coordenada inválida'
)$$), 'error:PT400', 'el RPC rechaza coordenadas fuera de rango');
select is(public.t_dml($$select * from public.registrar_reporte(
  '40000000-0000-0000-0000-000000000008',
  (select id from public.servicio where tipo = 'energia'),
  '11001', null, -74.07, 'Coordenada incompleta'
)$$), 'error:PT400', 'el RPC rechaza coordenadas incompletas');

reset role;
select public.t_como('c2222222-2222-2222-2222-222222222222');
select is(public.t_dml($$select * from public.registrar_reporte(
  '40000000-0000-0000-0000-000000000001',
  (select id from public.servicio where tipo = 'energia'),
  '11001', 4.65, -74.07, 'Intento con clave ajena'
)$$), 'error:PT409', 'no expone ni reutiliza la clave de otro ciudadano');

reset role;
select public.t_como('c3333333-3333-3333-3333-333333333333');
do $$
declare
  i integer;
begin
  for i in 1..5 loop
    perform * from public.registrar_reporte(
      ('50000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
      (select id from public.servicio where tipo = 'energia'),
      '11001', 4.65, -74.07, 'Reporte de prueba'
    );
  end loop;
end;
$$;
select is(public.t_dml($$select * from public.registrar_reporte(
  '50000000-0000-0000-0000-000000000006',
  (select id from public.servicio where tipo = 'energia'),
  '11001', 4.65, -74.07, 'Reporte que supera la cuota'
)$$), 'error:PT429', 'el sexto reporte por minuto se rechaza con HTTP 429');

reset role;
select public.t_anon();
select is(public.t_dml($$insert into public.reporte (
  client_request_id, servicio_id, ubicacion, descripcion
) values (
  gen_random_uuid(),
  (select id from public.servicio where tipo = 'energia'),
  extensions.st_setsrid(extensions.st_makepoint(-74.07, 4.65), 4326)::extensions.geography,
  'Sin municipio'
)$$), 'error:42501', 'un ciudadano anónimo no inserta reportes directamente');
select is(public.t_dml($$select public.registrar_denuncia(
  '60000000-0000-0000-0000-000000000001',
  (select id from public.servicio where tipo = 'energia'),
  '11001', 'Posible conexión irregular de servicio', 'codigo-seguimiento-1234567890'
)$$), 'ok:1', 'se permite el registro de denuncia dentro de la cuota');
do $$
declare
  i integer;
begin
  for i in 1..5 loop
    perform public.registrar_denuncia(
      '60000000-0000-0000-0000-000000000001',
      (select id from public.servicio where tipo = 'energia'),
      '11001', 'Posible conexión irregular de servicio', 'codigo-seguimiento-1234567890'
    );
  end loop;
end;
$$;
select ok(true, 'los reintentos idempotentes de denuncia no consumen cuota');
select is(public.t_dml($$select public.registrar_denuncia(
  '60000000-0000-0000-0000-000000000002',
  (select id from public.servicio where tipo = 'energia'),
  '11001', 'Otra posible conexión irregular', 'codigo-seguimiento-abcdefghij'
)$$), 'ok:1', 'se permite una segunda denuncia dentro de la cuota');
select is(public.t_dml($$select public.registrar_denuncia(
  '60000000-0000-0000-0000-000000000003',
  (select id from public.servicio where tipo = 'energia'),
  '11001', 'Tercera posible conexión irregular', 'codigo-seguimiento-klmnopqrst'
)$$), 'ok:1', 'se permite una tercera denuncia dentro de la cuota');
select is(public.t_dml($$select public.registrar_denuncia(
  '60000000-0000-0000-0000-000000000004',
  (select id from public.servicio where tipo = 'energia'),
  '11001', 'Cuarta posible conexión irregular', 'codigo-seguimiento-uvwxyzabcd'
)$$), 'error:PT429', 'la cuarta denuncia por IP en diez minutos se rechaza');

reset role;
select is(public.t_dml($$insert into public.reporte (
  client_request_id, servicio_id, municipio_codigo, ubicacion
) values (
  '80000000-0000-0000-0000-000000000001',
  (select id from public.servicio where tipo = 'energia'),
  null,
  extensions.st_setsrid(extensions.st_makepoint(-74.07, 4.65), 4326)::extensions.geography
)$$), 'error:23502', 'la base exige municipio en los reportes');
select is(public.t_dml($$insert into public.reporte (
  client_request_id, servicio_id, municipio_codigo, ubicacion, descripcion
) values (
  '80000000-0000-0000-0000-000000000002',
  (select id from public.servicio where tipo = 'energia'),
  '11001',
  extensions.st_setsrid(extensions.st_makepoint(-74.07, 4.65), 4326)::extensions.geography,
  '   '
)$$), 'error:23514', 'la base rechaza descripciones vacías');
update public.reporte
set estado = 'descartado'
where ciudadano_id = 'c1111111-1111-1111-1111-111111111111';
select is((select count(distinct sujeto_hash) from private.rate_limit_bucket where operacion = 'reporte_usuario'),
  2::bigint, 'los buckets guardan hashes por usuario y no identificadores directos');
select is((select count(distinct sujeto_hash) from private.rate_limit_bucket where operacion = 'reporte_ip'),
  1::bigint, 'los reportes también se limitan por IP');
select is((select count(distinct sujeto_hash) from private.rate_limit_bucket where operacion = 'denuncia'),
  1::bigint, 'las denuncias se agrupan por IP y ventana');
select is((select max_solicitudes from private.rate_limit_policy
  where operacion = 'reporte_usuario' and ventana_segundos = 60),
  5, 'las cuotas tienen una política configurable fuera del código del cliente');
select ok(
  not has_table_privilege('anon', 'private.rate_limit_bucket', 'SELECT')
  and not has_table_privilege('authenticated', 'private.rate_limit_bucket', 'SELECT'),
  'los clientes no pueden leer la tabla interna de límites'
);
do $$
declare
  i integer;
begin
  for i in 1..20 loop
    perform private.consumir_limite('prueba_cuota', 'cuota-ip-prueba', 60, 20);
  end loop;
end;
$$;
select is(public.t_dml($$select private.consumir_limite(
  'prueba_cuota', 'cuota-ip-prueba', 60, 20
)$$), 'error:PT429', 'la cuota por IP de reportes también bloquea el exceso');
select ok(
  (select count(*) = 1
   from public.audit_log
   where entidad = 'reporte'
     and correlation_id = '70000000-0000-0000-0000-000000000001'),
  'la auditoría conserva el correlation_id de la solicitud'
);

select * from finish();
rollback;
