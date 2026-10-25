-- SERVI-RED | Persona 1 | Fase 6a: alertas operativas (req. 29)

-- Tabla en el esquema no expuesto "private": el cliente nunca la ve.
create table private.alerta (
  id              bigint generated always as identity primary key,
  clave           text not null,
  tipo            text not null,
  severidad       text not null check (severidad in ('info', 'advertencia', 'critica')),
  mensaje         text not null,
  valor           numeric,
  abierta_en      timestamptz not null default now(),
  actualizada_en  timestamptz not null default now(),
  resuelta_en     timestamptz
);
-- Una sola alerta abierta por condición
create unique index alerta_clave_abierta_uidx on private.alerta (clave) where resuelta_en is null;
create index alerta_abierta_en_idx on private.alerta (abierta_en desc);
revoke all on private.alerta from public, anon, authenticated;

-- Revisa las reglas, abre las alertas nuevas, actualiza las vigentes y cierra
-- las que ya no se cumplen. Se puede ejecutar las veces que se quiera.
create or replace function private.evaluar_alertas()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  with condiciones as (
    -- 1. Eventos fallidos acumulados en el outbox
    select 'outbox_fallidos'::text as clave,
           'outbox_fallidos'::text as tipo,
           'critica'::text as severidad,
           format('Hay %s eventos fallidos en el outbox', f.n) as mensaje,
           f.n::numeric as valor
    from (select count(*) as n from public.evento_outbox where estado = 'fallido') f
    where f.n >= 3

    union all

    -- 2. Eventos pendientes sin procesar por más de 10 minutos (consumidor caído)
    select 'outbox_atrasado', 'outbox_atrasado', 'critica',
           format('El evento pendiente más antiguo lleva %s minutos sin procesarse',
                  round(extract(epoch from (now() - p.mas_antiguo)) / 60)),
           round(extract(epoch from (now() - p.mas_antiguo)) / 60)
    from (select min(creado_en) as mas_antiguo
          from public.evento_outbox where estado = 'pendiente') p
    where p.mas_antiguo < now() - interval '10 minutes'

    union all

    -- 3. Pico de reportes: posible caída masiva (20 o más en 10 minutos)
    select 'pico_reportes:' || s.tipo::text || ':' || r.municipio_codigo,
           'pico_reportes', 'advertencia',
           format('%s reportes de %s en el municipio %s en los últimos 10 minutos',
                  count(*), s.tipo, r.municipio_codigo),
           count(*)::numeric
    from public.reporte r
    join public.servicio s on s.id = r.servicio_id
    where r.creado_en >= now() - interval '10 minutes'
      and r.municipio_codigo is not null
    group by s.tipo, r.municipio_codigo
    having count(*) >= 20

    union all

    -- 4. Incidentes sin atender por más de 2 horas
    select 'incidentes_sin_atender', 'incidentes_sin_atender', 'advertencia',
           format('%s incidentes llevan más de 2 horas en estado recibido', i.n),
           i.n::numeric
    from (select count(*) as n from public.incidente
          where estado = 'recibido' and creado_en < now() - interval '2 hours') i
    where i.n > 0
  ),
  nuevas as (
    insert into private.alerta (clave, tipo, severidad, mensaje, valor)
    select c.clave, c.tipo, c.severidad, c.mensaje, c.valor from condiciones c
    on conflict (clave) where resuelta_en is null
    do update set severidad = excluded.severidad,
                  mensaje = excluded.mensaje,
                  valor = excluded.valor,
                  actualizada_en = now()
    returning id
  )
  update private.alerta a
  set resuelta_en = now(), actualizada_en = now()
  where a.resuelta_en is null
    and not exists (select 1 from condiciones c where c.clave = a.clave);

  -- Las alertas resueltas se conservan 30 días
  delete from private.alerta where resuelta_en < now() - interval '30 days';
end;
$$;
revoke all on function private.evaluar_alertas() from public, anon, authenticated;

-- Vistas para Superset (sin la columna clave)
create view metrics.alertas_activas as
select a.tipo, a.severidad, a.mensaje, a.valor, a.abierta_en, a.actualizada_en
from private.alerta a
where a.resuelta_en is null;

create view metrics.alertas_recientes as
select a.tipo, a.severidad, a.mensaje, a.abierta_en, a.resuelta_en,
       case when a.resuelta_en is null then 'activa' else 'resuelta' end as estado
from private.alerta a
where a.abierta_en >= now() - interval '7 days';

grant select on metrics.alertas_activas, metrics.alertas_recientes to metrics_reader;

-- Revisión automática cada 5 minutos. Si pg_cron no se puede configurar, avisa y sigue.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    begin
      create extension if not exists pg_cron with schema pg_catalog;
      perform cron.schedule('evaluar-alertas', '*/5 * * * *', 'select private.evaluar_alertas()');
    exception when others then
      raise notice 'No se pudo configurar pg_cron (%). Programar private.evaluar_alertas() a mano.', sqlerrm;
    end;
  else
    raise notice 'pg_cron no está disponible. Programar private.evaluar_alertas() a mano.';
  end if;
end $$;