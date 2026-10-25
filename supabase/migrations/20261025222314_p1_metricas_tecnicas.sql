-- SERVI-RED | Persona 1 | Fase 6c: métricas técnicas (req. 25, 26 y 28)

create extension if not exists pg_stat_statements with schema extensions;

-- Se lee con SECURITY DEFINER porque, sin permisos especiales, pg_stat_statements
-- oculta el texto de las consultas. Excluye consultas con datos delicados.
-- Si pg_stat_statements no está cargado, devuelve vacío en vez de fallar.
create or replace function private.consultas_lentas(p_limite integer default 20)
returns table (
  consulta         text,
  llamadas         bigint,
  tiempo_medio_ms  numeric,
  tiempo_max_ms    numeric,
  tiempo_total_ms  numeric,
  filas            bigint
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  select left(regexp_replace(s.query, '\s+', ' ', 'g'), 200),
         s.calls::bigint,
         round(s.mean_exec_time::numeric, 2),
         round(s.max_exec_time::numeric, 2),
         round(s.total_exec_time::numeric, 0),
         s.rows::bigint
  from extensions.pg_stat_statements s
  where s.dbid = (select d.oid from pg_catalog.pg_database d where d.datname = pg_catalog.current_database())
    and s.calls >= 5
    and s.query ~* '^\s*(select|insert|update|delete|with)\y'
    and s.query !~* '(password|secret|vault|token|pg_stat_statements|alter\s+role|create\s+role)'
    and s.userid not in (select r.oid from pg_catalog.pg_roles r
                         where r.rolname in ('metrics_reader', 'open_data_reader'))
  order by s.mean_exec_time desc
  limit p_limite;
exception
  when object_not_in_prerequisite_state or undefined_table then
    return;
end;
$$;
revoke all on function private.consultas_lentas(integer) from public, anon, authenticated;
grant execute on function private.consultas_lentas(integer) to metrics_reader;

create view metrics.consultas_lentas as
select * from private.consultas_lentas(20);

-- Uso de recursos frente a los límites del plan gratuito (500 MB de base de datos)
create view metrics.uso_recursos as
select
  round(pg_database_size(current_database()) / 1048576.0, 1)                      as base_datos_mb,
  500::numeric                                                                     as base_datos_limite_mb,
  round(100.0 * pg_database_size(current_database()) / (500 * 1048576.0), 1)       as base_datos_pct,
  round(coalesce((select sum((o.metadata ->> 'size')::bigint) from storage.objects o), 0)
        / 1048576.0, 1)                                                            as storage_mb,
  (select count(*) from storage.objects o)::bigint                                 as archivos,
  now()                                                                            as calculado_en;

grant select on metrics.consultas_lentas, metrics.uso_recursos to metrics_reader;