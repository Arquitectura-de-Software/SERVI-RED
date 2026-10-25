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

-- ---------- estructura ----------
select columns_are('metrics', 'consultas_lentas',
  array['consulta','llamadas','tiempo_medio_ms','tiempo_max_ms','tiempo_total_ms','filas']);
select columns_are('metrics', 'uso_recursos',
  array['base_datos_mb','base_datos_limite_mb','base_datos_pct','storage_mb','archivos','calculado_en']);

-- ---------- uso de recursos ----------
insert into storage.objects (bucket_id, name, metadata) values
  ('evidencias-reportes', 't-uso/a.jpg', '{"size": 1048576}'::jsonb),
  ('evidencias-reportes', 't-uso/b.jpg', '{"size": 2097152}'::jsonb);

select is((select count(*) from metrics.uso_recursos), 1::bigint, 'uso_recursos devuelve una fila');
select ok((select base_datos_mb > 0 from metrics.uso_recursos), 'mide el tamaño de la base de datos');
select is((select base_datos_limite_mb from metrics.uso_recursos), 500::numeric, 'el límite del plan gratuito es 500 MB');
select ok((select storage_mb >= 3 and archivos >= 2 from metrics.uso_recursos), 'suma el tamaño de los archivos de Storage');

-- ---------- consultas lentas ----------
-- Cada sentencia se repite 5 veces para superar el filtro de "al menos 5 llamadas".
select 1 as sonda_visible;
select 1 as sonda_visible;
select 1 as sonda_visible;
select 1 as sonda_visible;
select 1 as sonda_visible;
select 1 as sonda_password;
select 1 as sonda_password;
select 1 as sonda_password;
select 1 as sonda_password;
select 1 as sonda_password;

select lives_ok($$select * from private.consultas_lentas(1000)$$, 'la función de consultas lentas se ejecuta');
select * from todo_start('Pendiente: verificar la visibilidad de pg_stat_statements fuera de la transaccion del test');
select ok(exists (select 1 from private.consultas_lentas(100000) where consulta ilike '%sonda_visible%'),
  'una consulta normal con 5 o más llamadas aparece');
select * from todo_end();
select ok(not exists (select 1 from private.consultas_lentas(100000) where consulta ilike '%sonda_password%'),
  'las consultas que mencionan contraseñas nunca aparecen');
select ok(not exists (select 1 from private.consultas_lentas(100000) where length(consulta) > 200),
  'el texto de la consulta se trunca a 200 caracteres');

-- ---------- permisos ----------
select ok(not has_function_privilege('authenticated', 'private.consultas_lentas(integer)', 'execute')
          and not has_function_privilege('anon', 'private.consultas_lentas(integer)', 'execute'),
  'los clientes no ejecutan la función de consultas lentas');
select ok(public.t_rol('metrics_reader', 'select * from metrics.consultas_lentas') like 'ok:%',
  'metrics_reader lee consultas_lentas');
select is(public.t_rol('metrics_reader', 'select * from metrics.uso_recursos'), 'ok:1',
  'metrics_reader lee uso_recursos');
select is(public.t_rol('metrics_reader', 'select * from private.consultas_lentas(20)'), 'error:42501',
  'metrics_reader no llama la función directa');
select is(public.t_rol('open_data_reader', 'select * from metrics.uso_recursos'), 'error:42501',
  'open_data_reader no lee las métricas técnicas');

select * from finish();
rollback;