begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

create function public.t_dml(p_sql text) returns text language plpgsql as $$
declare n bigint;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return 'ok:' || n;
exception when others then return 'error:' || sqlstate;
end $$;
create function public.t_servidor() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  set local role service_role;
end $$;

-- ---------- 1. denuncia.creada ----------
insert into public.denuncia (id, client_request_id, servicio_id, municipio_codigo, descripcion, seguimiento_hash)
values ('30000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001',
        (select id from public.servicio where tipo = 'energia'), '11001',
        'Descripcion privada de la denuncia', 'hash-privado-de-prueba');

select is((select count(*) from public.evento_outbox where tipo = 'denuncia.creada'), 1::bigint,
  'crear una denuncia encola denuncia.creada');
select ok((select payload ?& array['denuncia_id','servicio_id','municipio_codigo','creado_en']
           from public.evento_outbox where tipo = 'denuncia.creada'),
  'el evento trae los campos necesarios para enrutar al operador');
select ok((select not (payload ? 'seguimiento_hash' or payload ? 'descripcion' or payload ? 'ubicacion_aprox'
                       or payload::text like '%hash-privado%' or payload::text like '%Descripcion privada%')
           from public.evento_outbox where tipo = 'denuncia.creada'),
  'el evento de denuncia no contiene hash ni contenido privado');

-- ---------- 2. límites por IP ----------
select is((select max_solicitudes from private.rate_limit_policy where operacion = 'reporte_ip' and ventana_segundos = 60),
  60, 'límite de reportes por IP: 60 por minuto');
select is((select max_solicitudes from private.rate_limit_policy where operacion = 'reporte_ip' and ventana_segundos = 86400),
  1000, 'límite de reportes por IP: 1000 por día');

-- ---------- 3. limpieza del outbox ----------
insert into public.evento_outbox (tipo, estado, procesado_en, creado_en) values
  ('t.viejo_procesado',    'procesado', now() - interval '8 days', now() - interval '9 days'),
  ('t.reciente_procesado', 'procesado', now() - interval '1 day',  now() - interval '2 days'),
  ('t.viejo_fallido',      'fallido',   null, now() - interval '31 days'),
  ('t.reciente_fallido',   'fallido',   null, now() - interval '2 days'),
  ('t.viejo_pendiente',    'pendiente', null, now() - interval '40 days');

select private.limpiar_outbox();

select is((select count(*) from public.evento_outbox where tipo = 't.viejo_procesado'), 0::bigint, 'borra procesados de más de 7 días');
select is((select count(*) from public.evento_outbox where tipo = 't.viejo_fallido'), 0::bigint, 'borra fallidos de más de 30 días');
select is((select count(*) from public.evento_outbox where tipo = 't.reciente_procesado'), 1::bigint, 'conserva procesados recientes');
select is((select count(*) from public.evento_outbox where tipo = 't.reciente_fallido'), 1::bigint, 'conserva fallidos recientes');
select is((select count(*) from public.evento_outbox where tipo = 't.viejo_pendiente'), 1::bigint, 'nunca borra eventos pendientes');
select ok(not has_function_privilege('authenticated', 'private.limpiar_outbox()', 'EXECUTE')
          and not has_function_privilege('anon', 'private.limpiar_outbox()', 'EXECUTE'),
  'los clientes no ejecutan la limpieza');

-- ---------- 4. reintentar un evento fallido ----------
insert into public.evento_outbox (tipo, estado, intentos, ultimo_error)
values ('t.reintento', 'fallido', 5, 'fallo anterior');
select set_config('test.evento_id', (select id::text from public.evento_outbox where tipo = 't.reintento'), true);

select ok(not has_function_privilege('anon', 'public.reintentar_evento_outbox(bigint)', 'EXECUTE')
          and not has_function_privilege('authenticated', 'public.reintentar_evento_outbox(bigint)', 'EXECUTE')
          and has_function_privilege('service_role', 'public.reintentar_evento_outbox(bigint)', 'EXECUTE'),
  'solo el servidor puede reencolar eventos');

select public.t_servidor();
select is(public.t_dml($$select public.reintentar_evento_outbox(current_setting('test.evento_id')::bigint)$$),
  'ok:1', 'service_role reencola un evento fallido');
select is(public.t_dml($$select public.reintentar_evento_outbox(current_setting('test.evento_id')::bigint)$$),
  'error:P0002', 'no reencola un evento que ya no está fallido');
reset role;

select is((select estado::text from public.evento_outbox where tipo = 't.reintento'), 'pendiente', 'el evento vuelve a pendiente');
select ok((select intentos = 0 and ultimo_error is null and lease_token is null
           from public.evento_outbox where tipo = 't.reintento'),
  'reencolar reinicia los intentos y limpia el error');

select * from finish();
rollback;