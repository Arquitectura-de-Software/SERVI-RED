begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

create function public.t_rol(p_rol text, p_sql text) returns text language plpgsql as $$
declare n bigint;
begin
  execute format('set local role %I', p_rol);
  begin
    execute p_sql;
    get diagnostics n = row_count;
    reset role;
    return 'ok:' || n;
  exception when others then
    reset role;
    return 'error:' || sqlstate;
  end;
end $$;

-- ---------- 1. eventos fallidos (umbral: 3) ----------
insert into public.evento_outbox (tipo, estado, intentos)
select 't.fallo', 'fallido', 5 from generate_series(1, 2);
select private.evaluar_alertas();
select is((select count(*) from private.alerta where tipo = 'outbox_fallidos' and resuelta_en is null),
  0::bigint, 'con 2 eventos fallidos no hay alerta');

insert into public.evento_outbox (tipo, estado, intentos) values ('t.fallo', 'fallido', 5);
select private.evaluar_alertas();
select is((select count(*) from private.alerta where tipo = 'outbox_fallidos' and resuelta_en is null),
  1::bigint, 'con 3 eventos fallidos se abre la alerta');
select is((select severidad from private.alerta where tipo = 'outbox_fallidos' and resuelta_en is null),
  'critica', 'la alerta de fallidos es crítica');
select is((select valor from private.alerta where tipo = 'outbox_fallidos' and resuelta_en is null),
  3::numeric, 'la alerta guarda cuántos eventos fallaron');

select private.evaluar_alertas();
select is((select count(*) from private.alerta where tipo = 'outbox_fallidos'),
  1::bigint, 'evaluar de nuevo no duplica la alerta');

delete from public.evento_outbox where tipo = 't.fallo';
select private.evaluar_alertas();
select is((select count(*) from private.alerta where tipo = 'outbox_fallidos' and resuelta_en is null),
  0::bigint, 'la alerta se cierra sola cuando la condición desaparece');
select is((select count(*) from private.alerta where tipo = 'outbox_fallidos' and resuelta_en is not null),
  1::bigint, 'la alerta cerrada queda en el historial');

-- ---------- 2. outbox atrasado (umbral: 10 minutos) ----------
insert into public.evento_outbox (tipo, estado, creado_en)
values ('t.pendiente', 'pendiente', now() - interval '1 minute');
select private.evaluar_alertas();
select is((select count(*) from private.alerta where tipo = 'outbox_atrasado' and resuelta_en is null),
  0::bigint, 'un evento pendiente reciente no genera alerta');

insert into public.evento_outbox (tipo, estado, creado_en)
values ('t.pendiente', 'pendiente', now() - interval '11 minutes');
select private.evaluar_alertas();
select is((select count(*) from private.alerta where tipo = 'outbox_atrasado' and resuelta_en is null),
  1::bigint, 'un evento pendiente de más de 10 minutos abre la alerta');

delete from public.evento_outbox where tipo = 't.pendiente';
select private.evaluar_alertas();
select is((select count(*) from private.alerta where tipo = 'outbox_atrasado' and resuelta_en is null),
  0::bigint, 'la alerta de atraso se cierra al vaciar los pendientes');

-- ---------- 3. pico de reportes (umbral: 20 en 10 minutos) ----------
insert into public.reporte (client_request_id, servicio_id, municipio_codigo, ubicacion, creado_en)
select gen_random_uuid(), (select id from public.servicio where tipo = 'energia'), '11001',
       extensions.st_setsrid(extensions.st_makepoint(-74.07, 4.65), 4326)::extensions.geography,
       now() - interval '2 minutes'
from generate_series(1, 19);
select private.evaluar_alertas();
select is((select count(*) from private.alerta where tipo = 'pico_reportes' and resuelta_en is null),
  0::bigint, '19 reportes no generan alerta');

insert into public.reporte (client_request_id, servicio_id, municipio_codigo, ubicacion, creado_en)
values (gen_random_uuid(), (select id from public.servicio where tipo = 'energia'), '11001',
        extensions.st_setsrid(extensions.st_makepoint(-74.07, 4.65), 4326)::extensions.geography,
        now() - interval '2 minutes');
select private.evaluar_alertas();
select is((select count(*) from private.alerta where tipo = 'pico_reportes' and resuelta_en is null),
  1::bigint, '20 reportes en el mismo servicio y municipio abren la alerta');
select is((select valor from private.alerta where tipo = 'pico_reportes' and resuelta_en is null),
  20::numeric, 'la alerta de pico guarda el número de reportes');
select ok((select mensaje like '%energia%11001%' from private.alerta where tipo = 'pico_reportes' and resuelta_en is null),
  'el mensaje nombra el servicio y el municipio');

-- ---------- 4. incidentes sin atender (umbral: 2 horas) ----------
insert into public.incidente (id, servicio_id, creado_en)
values ('20000000-0000-0000-0000-0000000000a1',
        (select id from public.servicio where tipo = 'energia'), now() - interval '3 hours');
select private.evaluar_alertas();
select is((select count(*) from private.alerta where tipo = 'incidentes_sin_atender' and resuelta_en is null),
  1::bigint, 'un incidente recibido hace 3 horas abre la alerta');

update public.incidente set estado = 'en_atencion' where id = '20000000-0000-0000-0000-0000000000a1';
select private.evaluar_alertas();
select is((select count(*) from private.alerta where tipo = 'incidentes_sin_atender' and resuelta_en is null),
  0::bigint, 'atender el incidente cierra la alerta');

-- ---------- 5. seguridad ----------
select ok(not has_table_privilege('authenticated', 'private.alerta', 'select')
          and not has_table_privilege('anon', 'private.alerta', 'select'),
  'los clientes no leen la tabla de alertas');
select ok(not has_function_privilege('authenticated', 'private.evaluar_alertas()', 'execute')
          and not has_function_privilege('anon', 'private.evaluar_alertas()', 'execute'),
  'los clientes no ejecutan la evaluación de alertas');

select columns_are('metrics', 'alertas_activas',
  array['tipo','severidad','mensaje','valor','abierta_en','actualizada_en']);
select columns_are('metrics', 'alertas_recientes',
  array['tipo','severidad','mensaje','abierta_en','resuelta_en','estado']);

select is(public.t_rol('metrics_reader', 'select * from metrics.alertas_activas'),
  'ok:' || (select count(*)::text from private.alerta where resuelta_en is null),
  'metrics_reader lee las alertas activas');
select is(public.t_rol('metrics_reader', 'select * from metrics.alertas_recientes'),
  'ok:' || (select count(*)::text from private.alerta where abierta_en >= now() - interval '7 days'),
  'metrics_reader lee las alertas recientes');
select is(public.t_rol('metrics_reader', 'select * from private.alerta'), 'error:42501',
  'metrics_reader no lee la tabla directa');
select is(public.t_rol('open_data_reader', 'select * from metrics.alertas_activas'), 'error:42501',
  'open_data_reader no lee las alertas');

select * from finish();
rollback;