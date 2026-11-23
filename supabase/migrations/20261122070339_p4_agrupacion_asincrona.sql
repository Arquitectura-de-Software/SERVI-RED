-- =====================================================================
-- SERVI-RED | Persona 4 | Agrupación asíncrona de reportes (ADR-03)
-- =====================================================================
-- ADR-03 y flujo 8.1 del SAD: la evaluación espacial ocurre DESPUÉS de
-- confirmar al ciudadano. Por eso se retira el trigger AFTER INSERT de
-- p4_agrupacion_incidentes y la agrupación pasa a un proceso en segundo plano:
--   * registrar_reporte (P1) confirma al ciudadano de inmediato; el reporte
--     queda en 'recibido' y sin incidente.
--   * pg_cron ejecuta private.agrupar_pendientes() cada 30 s, que vincula los
--     reportes pendientes con la misma regla de antes (servicio, municipio,
--     radio y ventana de config_agrupacion).
--   * Consistencia eventual: un reporte aparece en su incidente en <= 30 s.
-- Como el INSERT de un reporte ya no genera el incidente ni eventos extra en la
-- misma transacción, las pruebas de P1 que cuentan exacto no se ven afectadas.

-- ---------- 1. retirar el trigger síncrono ----------
drop trigger if exists p4_agrupar_reporte on public.reporte;
-- La función del trigger ya no se usa: la lógica vive en agrupar_reporte_uno.
drop function if exists private.agrupar_reporte();

-- ---------- 2. agrupar un reporte ----------
-- Misma regla de p4_agrupacion_incidentes, sin depender de NEW. No hace nada
-- si el reporte no existe, ya tiene incidente o no está en 'recibido'.
-- Devuelve el incidente al que quedó vinculado (null si no hizo nada).
create or replace function private.agrupar_reporte_uno(p_reporte_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rep        public.reporte%rowtype;
  v_radio      integer;
  v_ventana    interval;
  v_incidente  uuid;
  v_empresa    uuid;
  v_existente  boolean := false;
begin
  select * into v_rep from public.reporte r where r.id = p_reporte_id for update;
  if not found or v_rep.incidente_id is not null or v_rep.estado is distinct from 'recibido' then
    return null;
  end if;

  select p.radio_m, p.ventana into v_radio, v_ventana
  from private.parametros_agrupacion(v_rep.servicio_id) p;

  -- Serializa por servicio y municipio: dos procesos no crean dos incidentes
  -- para la misma falla.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'p4_agrupar:' || v_rep.servicio_id::text || ':' || v_rep.municipio_codigo, 0)
  );

  -- actualizado_en refleja la última actividad del incidente.
  select i.id into v_incidente
  from public.incidente i
  where i.servicio_id = v_rep.servicio_id
    and i.municipio_codigo = v_rep.municipio_codigo
    and i.estado in ('recibido', 'en_atencion')
    and i.centroide is not null
    and extensions.st_dwithin(i.centroide, v_rep.ubicacion, v_radio)
    and i.actualizado_en >= v_rep.creado_en - v_ventana
  order by extensions.st_distance(i.centroide, v_rep.ubicacion), i.creado_en
  limit 1;

  if v_incidente is null then
    select case when count(*) = 1 then (pg_catalog.array_agg(c.empresa_id))[1] end
      into v_empresa
    from public.empresa_cobertura c
    where c.servicio_id = v_rep.servicio_id
      and c.municipio_codigo = v_rep.municipio_codigo;

    insert into public.incidente (servicio_id, empresa_id, municipio_codigo, centroide, inicio_en)
    values (v_rep.servicio_id, v_empresa, v_rep.municipio_codigo, v_rep.ubicacion, v_rep.inicio_estimado)
    returning id into v_incidente;
  else
    v_existente := true;
  end if;

  update public.reporte
     set incidente_id = v_incidente,
         estado = 'vinculado'
   where id = v_rep.id;

  if v_existente then
    update public.incidente i
       set centroide = (
             select extensions.st_centroid(
                      extensions.st_collect(r.ubicacion::extensions.geometry)
                    )::extensions.geography
             from public.reporte r
             where r.incidente_id = v_incidente)
     where i.id = v_incidente;
  end if;

  return v_incidente;
end;
$$;

revoke all on function private.agrupar_reporte_uno(uuid) from public, anon, authenticated;

-- ---------- 3. procesar los pendientes ----------
-- En orden de llegada. SKIP LOCKED: si dos ejecuciones coinciden, cada una toma
-- reportes distintos y ninguna espera a la otra. Devuelve cuántos vinculó.
-- Sin permisos para clientes: la ejecuta postgres (pg_cron). No se da USAGE del
-- esquema private a service_role para no cambiar los permisos que definió P1.
create or replace function private.agrupar_pendientes(p_limite integer default 200)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id     uuid;
  v_total  integer := 0;
begin
  if p_limite is null or p_limite < 1 then
    return 0;
  end if;

  for v_id in
    select r.id
    from public.reporte r
    where r.incidente_id is null
      and r.estado = 'recibido'
    order by r.creado_en, r.id
    limit p_limite
    for update skip locked
  loop
    if private.agrupar_reporte_uno(v_id) is not null then
      v_total := v_total + 1;
    end if;
  end loop;

  return v_total;
end;
$$;

revoke all on function private.agrupar_pendientes(integer) from public, anon, authenticated;

create index if not exists reporte_pendiente_agrupar_idx
  on public.reporte (creado_en)
  where incidente_id is null and estado = 'recibido';

-- ---------- 4. programación con pg_cron ----------
-- Mismo patrón que P1: si pg_cron no está disponible, la migración no falla.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    begin
      create extension if not exists pg_cron with schema pg_catalog;
      if exists (select 1 from cron.job where jobname = 'p4-agrupar-reportes') then
        perform cron.unschedule('p4-agrupar-reportes');
      end if;
      perform cron.schedule('p4-agrupar-reportes', '30 seconds', 'select private.agrupar_pendientes()');
    exception when others then
      raise notice 'No se pudo configurar pg_cron (%). Programar private.agrupar_pendientes() a mano.', sqlerrm;
    end;
  else
    raise notice 'pg_cron no está disponible. Programar private.agrupar_pendientes() a mano.';
  end if;
end $$;
