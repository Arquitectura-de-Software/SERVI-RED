begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- Ejecuta una sentencia como otro rol y devuelve 'ok:<filas>' o 'error:<sqlstate>'.
-- Las aserciones se hacen como postgres, no como el rol de prueba.
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

-- Un dato para que las vistas tengan algo que contar
insert into auth.users (id) values ('c1111111-1111-1111-1111-111111111111');
insert into reporte (client_request_id, ciudadano_id, servicio_id, municipio_codigo, ubicacion)
values ('40000000-0000-0000-0000-000000000001', 'c1111111-1111-1111-1111-111111111111',
        (select id from servicio where tipo = 'energia'), '11001',
        extensions.st_setsrid(extensions.st_makepoint(-74.07, 4.65), 4326)::extensions.geography);

-- ---------- roles ----------
select has_role('metrics_reader',   'existe metrics_reader');
select has_role('open_data_reader', 'existe open_data_reader');
select is((select rolsuper or rolcreatedb or rolcreaterole from pg_roles where rolname = 'metrics_reader'),
  false, 'metrics_reader no tiene privilegios elevados');
select is((select rolsuper or rolcreatedb or rolcreaterole from pg_roles where rolname = 'open_data_reader'),
  false, 'open_data_reader no tiene privilegios elevados');

-- ---------- columnas de las vistas (sin datos personales) ----------
select columns_are('metrics', 'reportes_por_dia', array['fecha','servicio','estado','total']);
select columns_are('metrics', 'incidentes_abiertos', array['estado','servicio','total','mas_antiguo']);
select columns_are('metrics', 'eventos_outbox', array['tipo','estado','total','max_intentos','mas_antiguo']);
select columns_are('metrics', 'resumen_general',
  array['reportes_24h','incidentes_abiertos','eventos_fallidos','eventos_pendientes','calculado_en']);

-- ---------- metrics_reader ----------
select is(public.t_rol('metrics_reader', 'select * from metrics.resumen_general'), 'ok:1', 'metrics_reader lee el resumen');
select is(public.t_rol('metrics_reader', 'select * from metrics.reportes_por_dia'), 'ok:1', 'metrics_reader lee reportes por día');
select is(public.t_rol('metrics_reader', 'select * from metrics.eventos_outbox'), 'ok:1', 'metrics_reader lee eventos del outbox');
select is(public.t_rol('metrics_reader', 'select * from public.reporte'), 'error:42501', 'no lee reportes');
select is(public.t_rol('metrics_reader', 'select * from public.denuncia'), 'error:42501', 'no lee denuncias');
select is(public.t_rol('metrics_reader', 'select * from public.evento_outbox'), 'error:42501', 'no lee el outbox crudo');
select is(public.t_rol('metrics_reader', 'select * from public.audit_log'), 'error:42501', 'no lee audit_log');
select is(public.t_rol('metrics_reader', 'select * from public.perfil'), 'error:42501', 'no lee perfiles');
select is(public.t_rol('metrics_reader', 'select * from private.rate_limit_secret'), 'error:42501', 'no accede al esquema private');
select is(public.t_rol('metrics_reader', 'create table metrics.x (a int)'), 'error:42501', 'no crea objetos');
select is(public.t_rol('metrics_reader', 'select * from open_data.no_existe'), 'error:42501', 'no accede a open_data');

-- ---------- open_data_reader ----------
select is(public.t_rol('open_data_reader', 'select * from metrics.resumen_general'), 'error:42501', 'open_data_reader no lee metrics');
select is(public.t_rol('open_data_reader', 'select * from public.reporte'), 'error:42501', 'open_data_reader no lee reportes');
select is(public.t_rol('open_data_reader', 'select * from public.denuncia'), 'error:42501', 'open_data_reader no lee denuncias');
select is(public.t_rol('open_data_reader', 'create table open_data.x (a int)'), 'error:42501', 'open_data_reader no crea objetos');

-- ---------- las vistas cuentan lo esperado ----------
select ok((select reportes_24h from metrics.resumen_general) >= 1, 'el resumen cuenta el reporte de prueba');
select ok((select eventos_pendientes from metrics.resumen_general) >= 1, 'el resumen cuenta el evento pendiente del outbox');

select * from finish();
rollback;