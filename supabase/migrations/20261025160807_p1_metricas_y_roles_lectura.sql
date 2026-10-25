-- SERVI-RED | Persona 1 | Fase 5a: esquemas metrics y open_data, roles de solo lectura

-- ---------- roles ----------
-- Se crean con LOGIN pero SIN contraseña: no pueden iniciar sesión hasta que
-- la Persona 1 les ponga una a mano (nunca en el repositorio).
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'metrics_reader') then
    create role metrics_reader login nosuperuser nocreatedb nocreaterole noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'open_data_reader') then
    create role open_data_reader login nosuperuser nocreatedb nocreaterole noinherit;
  end if;
end $$;

alter role metrics_reader   set default_transaction_read_only = on;
alter role metrics_reader   set statement_timeout = '30s';
alter role metrics_reader   set search_path = metrics;
alter role metrics_reader   connection limit 10;
alter role open_data_reader set default_transaction_read_only = on;
alter role open_data_reader set statement_timeout = '30s';
alter role open_data_reader set search_path = open_data;
alter role open_data_reader connection limit 10;

-- Permite que postgres use SET ROLE sobre ellos (necesario para las pruebas)
grant metrics_reader   to postgres;
grant open_data_reader to postgres;

-- ---------- esquemas ----------
create schema if not exists metrics;
create schema if not exists open_data;
revoke all on schema metrics, open_data from public, anon, authenticated;

grant usage on schema metrics   to metrics_reader;
grant usage on schema open_data to open_data_reader;

-- Todo lo que se cree después en open_data (vistas de la Persona 5) será legible
-- por open_data_reader sin tocar esta migración.
alter default privileges in schema open_data grant select on tables to open_data_reader;

-- ---------- vistas de métricas operativas (req. 26) ----------
-- Solo agregados: sin ciudadanos, descripciones, ubicaciones ni hashes.
create view metrics.reportes_por_dia as
select (r.creado_en at time zone 'America/Bogota')::date as fecha,
       s.tipo::text   as servicio,
       r.estado::text as estado,
       count(*)::bigint as total
from public.reporte r
join public.servicio s on s.id = r.servicio_id
group by 1, 2, 3;

create view metrics.incidentes_abiertos as
select i.estado::text as estado,
       s.tipo::text   as servicio,
       count(*)::bigint as total,
       min(i.creado_en) as mas_antiguo
from public.incidente i
join public.servicio s on s.id = i.servicio_id
where i.estado <> 'cerrado'
group by 1, 2;

-- Los eventos con estado 'fallido' son las notificaciones fallidas.
create view metrics.eventos_outbox as
select e.tipo,
       e.estado::text as estado,
       count(*)::bigint as total,
       max(e.intentos)  as max_intentos,
       min(e.creado_en) as mas_antiguo
from public.evento_outbox e
group by 1, 2;

create view metrics.resumen_general as
select
  (select count(*) from public.reporte where creado_en >= now() - interval '24 hours')::bigint as reportes_24h,
  (select count(*) from public.incidente where estado <> 'cerrado')::bigint                    as incidentes_abiertos,
  (select count(*) from public.evento_outbox where estado = 'fallido')::bigint                 as eventos_fallidos,
  (select count(*) from public.evento_outbox where estado = 'pendiente')::bigint               as eventos_pendientes,
  now() as calculado_en;

grant select on all tables in schema metrics to metrics_reader;
alter default privileges in schema metrics grant select on tables to metrics_reader;