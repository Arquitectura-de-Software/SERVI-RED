-- =====================================================================
-- SERVI-RED | Persona 4 | Agrupación automática de reportes en incidentes
-- =====================================================================
-- Cada reporte nuevo se vincula a un incidente abierto del mismo servicio y
-- municipio que esté a menos de `radio_m` metros de su centroide y que haya
-- tenido actividad en las últimas `ventana_horas`. Si no hay ninguno, se crea
-- un incidente nuevo. El trigger es el único que escribe reporte.incidente_id
-- de forma automática (el operador o el admin pueden corregirlo después).
--
-- Decisiones pendientes de confirmar (ver mensajes de coordinación P4):
--   * Valores iniciales de radio y ventana (propuestos, no salen del SRS).
--   * empresa_id: se asigna solo si exactamente una empresa cubre el servicio
--     en el municipio; si hay 0 o varias queda null y lo asigna un admin.
--   * Solo se agrupa en incidentes 'recibido' o 'en_atencion'.

-- ---------- 1. parámetros por tipo de servicio ----------
-- Se indexa por tipo (enum) y no por servicio.id porque los servicios se cargan
-- en seed.sql, después de las migraciones.
create table public.config_agrupacion (
  servicio_tipo   public.tipo_servicio primary key,
  radio_m         integer not null check (radio_m between 10 and 20000),
  ventana_horas   integer not null check (ventana_horas between 1 and 168),
  actualizado_en  timestamptz not null default now()
);

comment on table public.config_agrupacion is
  'P4: radio (m) y ventana (h) para agrupar reportes en incidentes, por tipo de servicio.';

insert into public.config_agrupacion (servicio_tipo, radio_m, ventana_horas) values
  ('energia',        1000, 6),
  ('gas',             500, 6),
  ('acueducto',       500, 6),
  ('alcantarillado',  500, 6),
  ('aseo',            500, 6);

alter table public.config_agrupacion enable row level security;

-- Lectura para cualquier sesión (no es sensible y la app puede mostrarla);
-- solo el admin la cambia.
create policy config_agrupacion_select on public.config_agrupacion
  for select to authenticated using (true);

create policy config_agrupacion_admin on public.config_agrupacion
  for all to authenticated
  using ((select public.rol_actual()) = 'admin')
  with check ((select public.rol_actual()) = 'admin');

revoke all on public.config_agrupacion from anon;
revoke all on public.config_agrupacion from authenticated;
grant select on public.config_agrupacion to authenticated;
grant insert, update (radio_m, ventana_horas, actualizado_en), delete
  on public.config_agrupacion to authenticated;

-- ---------- 2. parámetros efectivos para un servicio ----------
-- Si falta la fila de configuración, se usan 500 m y 6 h.
create or replace function private.parametros_agrupacion(p_servicio_id smallint)
returns table (radio_m integer, ventana interval)
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(c.radio_m, 500),
         pg_catalog.make_interval(hours => coalesce(c.ventana_horas, 6))
  from (select 1) uno
  left join public.servicio s on s.id = p_servicio_id
  left join public.config_agrupacion c on c.servicio_tipo = s.tipo
$$;

revoke all on function private.parametros_agrupacion(smallint) from public, anon, authenticated;

-- ---------- 3. trigger de agrupación ----------
create or replace function private.agrupar_reporte()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_radio      integer;
  v_ventana    interval;
  v_incidente  uuid;
  v_empresa    uuid;
  v_existente  boolean := false;
begin
  -- Reportes cargados ya vinculados o en otro estado (p. ej. por un admin) no se tocan.
  if new.incidente_id is not null or new.estado is distinct from 'recibido' then
    return null;
  end if;

  select p.radio_m, p.ventana into v_radio, v_ventana
  from private.parametros_agrupacion(new.servicio_id) p;

  -- Serializa la agrupación por servicio y municipio para que dos reportes
  -- simultáneos no creen dos incidentes para la misma falla.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'p4_agrupar:' || new.servicio_id::text || ':' || new.municipio_codigo, 0)
  );

  -- actualizado_en refleja la última actividad: cada reporte vinculado y cada
  -- gestión del operador lo renuevan.
  select i.id into v_incidente
  from public.incidente i
  where i.servicio_id = new.servicio_id
    and i.municipio_codigo = new.municipio_codigo
    and i.estado in ('recibido', 'en_atencion')
    and i.centroide is not null
    and extensions.st_dwithin(i.centroide, new.ubicacion, v_radio)
    and i.actualizado_en >= new.creado_en - v_ventana
  order by extensions.st_distance(i.centroide, new.ubicacion), i.creado_en
  limit 1;

  if v_incidente is null then
    select case when count(*) = 1 then (pg_catalog.array_agg(c.empresa_id))[1] end
      into v_empresa
    from public.empresa_cobertura c
    where c.servicio_id = new.servicio_id
      and c.municipio_codigo = new.municipio_codigo;

    insert into public.incidente (servicio_id, empresa_id, municipio_codigo, centroide, inicio_en)
    values (new.servicio_id, v_empresa, new.municipio_codigo, new.ubicacion, new.inicio_estimado)
    returning id into v_incidente;
  else
    v_existente := true;
  end if;

  update public.reporte
     set incidente_id = v_incidente,
         estado = 'vinculado'
   where id = new.id;

  if v_existente then
    -- El centroide es el centro de todos los reportes vinculados.
    update public.incidente i
       set centroide = (
             select extensions.st_centroid(
                      extensions.st_collect(r.ubicacion::extensions.geometry)
                    )::extensions.geography
             from public.reporte r
             where r.incidente_id = v_incidente)
     where i.id = v_incidente;
  end if;

  return null;
end;
$$;

revoke all on function private.agrupar_reporte() from public, anon, authenticated;

create trigger p4_agrupar_reporte
  after insert on public.reporte
  for each row execute function private.agrupar_reporte();

-- ---------- 4. consulta de incidentes cercanos (para la app / P2) ----------
-- Usa los mismos parámetros que el trigger. Se ejecuta con los permisos de quien
-- llama: incidente, servicio y config_agrupacion son legibles para cualquier sesión.
create or replace function public.incidentes_cercanos(
  p_servicio_id smallint,
  p_lat double precision,
  p_lng double precision
)
returns table (
  incidente_id    uuid,
  estado          public.estado_incidente,
  distancia_m     double precision,
  creado_en       timestamptz,
  actualizado_en  timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  with punto as (
    select extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography as g
    where p_lat between -90 and 90 and p_lng between -180 and 180
  ),
  cfg as (
    select coalesce(c.radio_m, 500) as radio_m,
           pg_catalog.make_interval(hours => coalesce(c.ventana_horas, 6)) as ventana
    from (select 1) uno
    left join public.servicio s on s.id = p_servicio_id
    left join public.config_agrupacion c on c.servicio_tipo = s.tipo
  )
  select i.id, i.estado, extensions.st_distance(i.centroide, punto.g), i.creado_en, i.actualizado_en
  from public.incidente i, punto, cfg
  where i.servicio_id = p_servicio_id
    and i.estado in ('recibido', 'en_atencion')
    and i.centroide is not null
    and extensions.st_dwithin(i.centroide, punto.g, cfg.radio_m)
    and i.actualizado_en >= now() - cfg.ventana
  order by 3
  limit 5
$$;

revoke all on function public.incidentes_cercanos(smallint, double precision, double precision) from public, anon;
grant execute on function public.incidentes_cercanos(smallint, double precision, double precision) to authenticated;
