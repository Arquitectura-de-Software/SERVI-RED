-- =====================================================================
-- SERVI-RED | Persona 1 | Fase 4: Consultas geoespaciales y proximidad
-- Requisito 3 & 5: Mapa de incidentes cercanos con PostGIS ST_DWithin
-- =====================================================================

-- 1. Consultar incidentes cercanos dentro de un radio geográfico dado
create or replace function public.consultar_incidentes_cercanos(
  p_lat double precision,
  p_lng double precision,
  p_radio_metros double precision default 25000.0
)
returns table (
  id uuid,
  servicio_id smallint,
  municipio_codigo char(5),
  lat double precision,
  lng double precision,
  estado public.estado_incidente,
  prioridad smallint,
  creado_en timestamptz,
  distancia_metros double precision
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_origen extensions.geography;
begin
  if p_lat is null or p_lng is null then
    raise exception 'Las coordenadas son obligatorias' using errcode = 'PT400';
  end if;

  v_origen := extensions.st_setsrid(
    extensions.st_makepoint(p_lng, p_lat), 4326
  )::extensions.geography;

  return query
  select
    i.id,
    i.servicio_id,
    i.municipio_codigo,
    extensions.st_y(i.centroide::extensions.geometry) as lat,
    extensions.st_x(i.centroide::extensions.geometry) as lng,
    i.estado,
    i.prioridad,
    i.creado_en,
    extensions.st_distance(i.centroide, v_origen) as distancia_metros
  from public.incidente i
  where i.centroide is not null
    and extensions.st_dwithin(i.centroide, v_origen, coalesce(p_radio_metros, 25000.0))
  order by distancia_metros asc
  limit 100;
end;
$$;

revoke all on function public.consultar_incidentes_cercanos(double precision, double precision, double precision) from public;
grant execute on function public.consultar_incidentes_cercanos(double precision, double precision, double precision) to authenticated, anon;


-- 2. Consultar reportes cercanos públicos/anonimizados para visualización comunitaria
create or replace function public.consultar_reportes_cercanos(
  p_lat double precision,
  p_lng double precision,
  p_radio_metros double precision default 25000.0
)
returns table (
  id uuid,
  servicio_id smallint,
  municipio_codigo char(5),
  lat double precision,
  lng double precision,
  estado public.estado_reporte,
  descripcion text,
  creado_en timestamptz,
  distancia_metros double precision
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_origen extensions.geography;
begin
  if p_lat is null or p_lng is null then
    raise exception 'Las coordenadas son obligatorias' using errcode = 'PT400';
  end if;

  v_origen := extensions.st_setsrid(
    extensions.st_makepoint(p_lng, p_lat), 4326
  )::extensions.geography;

  return query
  select
    r.id,
    r.servicio_id,
    r.municipio_codigo,
    extensions.st_y(r.ubicacion::extensions.geometry) as lat,
    extensions.st_x(r.ubicacion::extensions.geometry) as lng,
    r.estado,
    r.descripcion,
    r.creado_en,
    extensions.st_distance(r.ubicacion, v_origen) as distancia_metros
  from public.reporte r
  where extensions.st_dwithin(r.ubicacion, v_origen, coalesce(p_radio_metros, 25000.0))
  order by distancia_metros asc
  limit 100;
end;
$$;

revoke all on function public.consultar_reportes_cercanos(double precision, double precision, double precision) from public;
grant execute on function public.consultar_reportes_cercanos(double precision, double precision, double precision) to authenticated, anon;
