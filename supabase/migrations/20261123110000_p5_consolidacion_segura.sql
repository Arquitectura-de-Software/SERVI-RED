-- Persona 5: agregados públicos sin datos personales, sobre el esquema real de SERVI-RED.
create schema if not exists open_data;
create materialized view open_data.p5_continuidad as
select date_trunc('month',i.creado_en)::date as mes,
 i.servicio_id, s.tipo::text as servicio, i.municipio_codigo,
 m.nombre as municipio, d.codigo_dane as departamento_codigo, d.nombre as departamento,
 count(*)::integer as incidentes,
 round(avg(extract(epoch from (i.restablecido_en-i.inicio_en))/3600.0)::numeric,2) as horas_promedio_interrupcion,
 round(avg(extract(epoch from (i.restablecido_en-i.inicio_en))/60.0)::numeric,2) as minutos_promedio_restauracion
from public.incidente i
join public.servicio s on s.id=i.servicio_id
left join public.municipio m on m.codigo_dane=i.municipio_codigo
left join public.departamento d on d.codigo_dane=m.departamento_codigo
where i.inicio_en is null or i.restablecido_en is null or i.restablecido_en>=i.inicio_en
group by 1,2,3,4,5,6,7
with data;
create unique index p5_continuidad_unique on open_data.p5_continuidad(mes,servicio_id,municipio_codigo);
create materialized view open_data.p5_llenado as
select date_trunc('month',r.creado_en)::date as mes,
 r.servicio_id,s.tipo::text as servicio,r.municipio_codigo,
 m.nombre as municipio,d.codigo_dane as departamento_codigo,d.nombre as departamento,
 count(*)::integer as reportes,
 round(100.0*count(*) filter(where r.descripcion is not null and btrim(r.descripcion)<>'' and r.inicio_estimado is not null)/nullif(count(*),0),2) as porcentaje_llenado
from public.reporte r join public.servicio s on s.id=r.servicio_id
left join public.municipio m on m.codigo_dane=r.municipio_codigo
left join public.departamento d on d.codigo_dane=m.departamento_codigo
group by 1,2,3,4,5,6,7
with data;
create unique index p5_llenado_unique on open_data.p5_llenado(mes,servicio_id,municipio_codigo);
-- Las vistas materializadas no se exponen directamente a anon/authenticated.
revoke all on open_data.p5_continuidad,open_data.p5_llenado from public,anon,authenticated;
-- Función de actualización solo para roles privilegiados.
create or replace function open_data.p5_actualizar() returns void language plpgsql security definer set search_path=pg_catalog,public,open_data as $$
begin
 refresh materialized view open_data.p5_continuidad;
 refresh materialized view open_data.p5_llenado;
end $$;
revoke all on function open_data.p5_actualizar() from public,anon,authenticated;
-- Proyección pública: solo celdas con al menos 5 observaciones.
create or replace function public.p5_indicadores_publicos() returns table(mes date,servicio text,municipio text,departamento text,incidentes integer,horas_promedio_interrupcion numeric,minutos_promedio_restauracion numeric,reportes integer,porcentaje_llenado numeric)
language sql stable security definer set search_path=pg_catalog,public,open_data as $$
select c.mes,c.servicio,c.municipio,c.departamento,c.incidentes,c.horas_promedio_interrupcion,c.minutos_promedio_restauracion,
 coalesce(l.reportes,0),case when l.reportes>=5 then l.porcentaje_llenado else null end
from open_data.p5_continuidad c left join open_data.p5_llenado l
on l.mes=c.mes and l.servicio_id=c.servicio_id and l.municipio_codigo is not distinct from c.municipio_codigo
where c.incidentes>=5 and c.municipio_codigo is not null;
$$;
revoke all on function public.p5_indicadores_publicos() from public;
grant execute on function public.p5_indicadores_publicos() to anon,authenticated;
-- Cron se configura por separado después de comprobar que la extensión está activa.
