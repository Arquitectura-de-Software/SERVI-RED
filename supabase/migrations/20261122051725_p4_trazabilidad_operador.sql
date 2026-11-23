-- =====================================================================
-- SERVI-RED | Persona 4 | Trazabilidad para el operador y exportación regulatoria
-- =====================================================================
-- 1. linea_tiempo_incidente(): la historia de un incidente para el portal.
--    audit_log solo lo lee el admin (P1), así que esta función lo expone filtrado:
--    solo eventos del incidente pedido y solo campos no personales.
-- 2. exportar_incidentes(): una fila por incidente para informes a SSPD / CRA / CREG.
--    FORMATO PROVISIONAL (no hay formato oficial del curso); documentado en
--    "PERSONA 4.md". Con `Accept: text/csv`, PostgREST devuelve el CSV directo.
--    Cada exportación queda en audit_log (req. 19).
-- Nunca se exponen: ciudadano_id, descripciones de reportes, hash de seguimiento
-- ni coordenadas exactas.
-- Respuestas "difundidas" (responder con p_a_reportes, ver p4_ajustes_operacion):
-- son una fila por reporte con el mismo operador, mensaje y fecha; aquí se
-- cuentan y se muestran una sola vez.

-- ---------- ayudante: nombre visible de un actor ----------
create or replace function private.actor_visible(p_actor uuid)
returns table (rol text, nombre text)
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(p.rol::text, 'sistema'),
         case when p.rol = 'operador' then o.nombre_completo
              when p.rol = 'admin'    then 'Administrador'
         end
  from (select 1) uno
  left join public.perfil p   on p.id = p_actor
  left join public.operador o on o.id = p_actor
$$;
revoke all on function private.actor_visible(uuid) from public, anon, authenticated;

-- ---------- 1. línea de tiempo ----------
create or replace function public.linea_tiempo_incidente(p_incidente_id uuid)
returns table (
  ocurrido_en   timestamptz,
  orden         bigint,
  tipo          text,
  descripcion   text,
  actor_rol     text,
  actor_nombre  text,
  detalle       jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rol     public.rol_usuario := public.rol_actual();
  v_empresa uuid;
begin
  perform private.correlation_id_actual();
  if v_rol is null or v_rol not in ('operador', 'regulador', 'admin') then
    raise exception 'Solo operadores, reguladores y administradores ven la línea de tiempo'
      using errcode = '42501';
  end if;

  select i.empresa_id into v_empresa from public.incidente i where i.id = p_incidente_id;
  if not found then
    raise exception 'El incidente no existe' using errcode = 'PT404';
  end if;
  if v_rol = 'operador' and v_empresa is distinct from public.empresa_actual() then
    raise exception 'El incidente no es de su empresa' using errcode = '42501';
  end if;

  return query
  with aud as (
    select a.id, a.creado_en, a.actor_id, a.accion, a.entidad, a.entidad_id, a.antes, a.despues
    from public.audit_log a
    where (a.entidad = 'incidente' and a.entidad_id = p_incidente_id)
       or (a.entidad = 'reporte' and (a.antes ->> 'incidente_id' = p_incidente_id::text
                                   or a.despues ->> 'incidente_id' = p_incidente_id::text))
  ),
  reportes_del_incidente as (
    select (a.entidad_id) as reporte_id from aud a where a.entidad = 'reporte'
    union
    select r.id from public.reporte r where r.incidente_id = p_incidente_id
  ),
  eventos as (
    -- creación
    select a.creado_en, a.id, 'incidente_creado'::text as tipo,
           'Se creó el incidente a partir de un reporte'::text as descripcion,
           'sistema'::text as actor_rol, null::text as actor_nombre,
           jsonb_build_object('estado', a.despues ->> 'estado', 'prioridad', (a.despues ->> 'prioridad')::int) as detalle
    from aud a where a.entidad = 'incidente' and a.accion = 'insert'

    union all -- estado
    select a.creado_en, a.id, 'estado_cambiado',
           'Estado: ' || (a.antes ->> 'estado') || ' → ' || (a.despues ->> 'estado'),
           av.rol, av.nombre,
           jsonb_build_object('desde', a.antes ->> 'estado', 'hacia', a.despues ->> 'estado')
    from aud a cross join lateral private.actor_visible(a.actor_id) av
    where a.entidad = 'incidente' and a.accion = 'update'
      and a.antes ->> 'estado' is distinct from a.despues ->> 'estado'

    union all -- prioridad
    select a.creado_en, a.id, 'prioridad_cambiada',
           'Prioridad: ' || (a.antes ->> 'prioridad') || ' → ' || (a.despues ->> 'prioridad'),
           av.rol, av.nombre,
           jsonb_build_object('desde', (a.antes ->> 'prioridad')::int, 'hacia', (a.despues ->> 'prioridad')::int)
    from aud a cross join lateral private.actor_visible(a.actor_id) av
    where a.entidad = 'incidente' and a.accion = 'update'
      and a.antes ->> 'prioridad' is distinct from a.despues ->> 'prioridad'

    union all -- asignación
    select a.creado_en, a.id, 'asignacion_cambiada',
           case when a.despues ->> 'operador_asignado' is null then 'Se quitó la asignación'
                else 'Asignado a ' || coalesce(o.nombre_completo, 'operador') end,
           av.rol, av.nombre,
           jsonb_build_object('operador_id', a.despues ->> 'operador_asignado', 'operador_nombre', o.nombre_completo)
    from aud a
    cross join lateral private.actor_visible(a.actor_id) av
    left join public.operador o on o.id = (a.despues ->> 'operador_asignado')::uuid
    where a.entidad = 'incidente' and a.accion = 'update'
      and a.antes ->> 'operador_asignado' is distinct from a.despues ->> 'operador_asignado'

    union all -- empresa
    select a.creado_en, a.id, 'empresa_cambiada',
           'Empresa responsable: ' || coalesce(e.nombre, '(ninguna)'),
           av.rol, av.nombre,
           jsonb_build_object('empresa_id', a.despues ->> 'empresa_id', 'empresa', e.nombre)
    from aud a
    cross join lateral private.actor_visible(a.actor_id) av
    left join public.empresa e on e.id = (a.despues ->> 'empresa_id')::uuid
    where a.entidad = 'incidente' and a.accion = 'update'
      and a.antes ->> 'empresa_id' is distinct from a.despues ->> 'empresa_id'

    union all -- reporte vinculado (agrupación automática)
    select a.creado_en, a.id, 'reporte_vinculado', 'Llegó un reporte ciudadano',
           'sistema', null,
           jsonb_build_object('reporte_id', a.entidad_id)
    from aud a
    where a.entidad = 'reporte'
      and a.despues ->> 'incidente_id' = p_incidente_id::text
      and a.antes ->> 'incidente_id' is distinct from p_incidente_id::text

    union all -- reportes que entraron ya vinculados (sin auditoría de vinculación)
    select r.creado_en, 0, 'reporte_vinculado', 'Llegó un reporte ciudadano', 'sistema', null,
           jsonb_build_object('reporte_id', r.id)
    from public.reporte r
    where r.incidente_id = p_incidente_id
      and not exists (select 1 from aud a where a.entidad = 'reporte' and a.entidad_id = r.id
                        and a.despues ->> 'incidente_id' = p_incidente_id::text)

    union all -- reporte desvinculado (descartado por moderación)
    select a.creado_en, a.id, 'reporte_desvinculado', 'Se descartó un reporte',
           av.rol, av.nombre,
           jsonb_build_object('reporte_id', a.entidad_id, 'estado', a.despues ->> 'estado')
    from aud a cross join lateral private.actor_visible(a.actor_id) av
    where a.entidad = 'reporte'
      and a.antes ->> 'incidente_id' = p_incidente_id::text
      and a.despues ->> 'incidente_id' is distinct from p_incidente_id::text

    union all -- moderación de los reportes del incidente
    -- orden = id de su propia fila de auditoría, para desempatar con los demás eventos.
    select v.fecha,
           coalesce((select min(al.id) from public.audit_log al
                     where al.entidad = 'validacion' and al.entidad_id = v.id), 0),
           'reporte_moderado',
           case v.estado when 'aprobada' then 'Reporte aprobado' else 'Reporte rechazado' end
             || coalesce(': ' || v.comentario, ''),
           av.rol, av.nombre,
           jsonb_build_object('reporte_id', v.reporte_id, 'decision', v.estado, 'comentario', v.comentario)
    from public.validacion v
    cross join lateral private.actor_visible(v.operador_id) av
    where v.reporte_id in (select reporte_id from reportes_del_incidente)

    union all -- respuestas del operador (una difusión a varios reportes cuenta una vez)
    select g.fecha_resp,
           coalesce((select min(al.id) from public.audit_log al
                     where al.entidad = 'respuesta' and al.entidad_id = g.id), 0),
           'respuesta', g.mensaje,
           av.rol, av.nombre,
           jsonb_build_object('respuesta_id', g.id, 'reporte_id', g.reporte_id,
                              'reportes_notificados', g.notificados)
    from (
      select distinct on (rs.operador_id, rs.mensaje, rs.fecha_resp)
             rs.id, rs.operador_id, rs.mensaje, rs.fecha_resp, rs.reporte_id,
             count(rs.reporte_id) over (partition by rs.operador_id, rs.mensaje, rs.fecha_resp)::int as notificados
      from public.respuesta rs
      where rs.incidente_id = p_incidente_id
         or rs.reporte_id in (select reporte_id from reportes_del_incidente)
      -- Se muestra la fila principal (la del incidente, sin reporte) si existe.
      order by rs.operador_id, rs.mensaje, rs.fecha_resp, (rs.reporte_id is not null), rs.id
    ) g
    cross join lateral private.actor_visible(g.operador_id) av
  )
  select ev.creado_en, ev.id, ev.tipo, ev.descripcion, ev.actor_rol, ev.actor_nombre, ev.detalle
  from eventos ev
  order by ev.creado_en, ev.id, ev.tipo;
end;
$$;

revoke all on function public.linea_tiempo_incidente(uuid) from public, anon;
grant execute on function public.linea_tiempo_incidente(uuid) to authenticated;

-- ---------- 2. exportación regulatoria (formato provisional) ----------
-- Fechas en hora de Colombia (America/Bogota), sin zona, para que Excel las lea.
-- Volátil (registra la exportación en audit_log): PostgREST la llama con POST.
create or replace function public.exportar_incidentes(
  p_desde       date,
  p_hasta       date,
  p_servicio_id smallint default null,
  p_empresa_id  uuid     default null
)
returns table (
  incidente_id          uuid,
  servicio              text,
  empresa_nit           text,
  empresa               text,
  departamento_dane     text,
  municipio_dane        text,
  municipio             text,
  estado                text,
  prioridad             smallint,
  reportado_en          timestamp,
  inicio_en             timestamp,
  restablecido_en       timestamp,
  cerrado_en            timestamp,
  duracion_horas        numeric,
  horas_hasta_atencion  numeric,
  total_reportes        integer,
  total_respuestas      integer,
  reabierto             text
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_rol     public.rol_usuario := public.rol_actual();
  v_empresa uuid := p_empresa_id;
  v_filas   bigint;
  v_tz      constant text := 'America/Bogota';
begin
  perform private.correlation_id_actual();
  if v_rol is null or v_rol not in ('operador', 'regulador', 'admin') then
    raise exception 'Solo operadores, reguladores y administradores exportan' using errcode = '42501';
  end if;
  if p_desde is null or p_hasta is null or p_hasta < p_desde then
    raise exception 'Indique un rango de fechas válido (desde <= hasta)' using errcode = 'PT400';
  end if;
  if p_hasta - p_desde > 366 then
    raise exception 'El rango máximo es de un año' using errcode = 'PT400';
  end if;

  -- Un operador solo exporta lo de su empresa.
  if v_rol = 'operador' then
    if p_empresa_id is not null and p_empresa_id is distinct from public.empresa_actual() then
      raise exception 'Un operador solo exporta los incidentes de su empresa' using errcode = '42501';
    end if;
    v_empresa := public.empresa_actual();
  end if;

  return query
  select
    i.id,
    s.tipo::text,
    e.nit,
    e.nombre,
    m.departamento_codigo::text,
    i.municipio_codigo::text,
    m.nombre,
    i.estado::text,
    i.prioridad,
    date_trunc('second', i.creado_en       at time zone v_tz),
    date_trunc('second', i.inicio_en       at time zone v_tz),
    date_trunc('second', i.restablecido_en at time zone v_tz),
    date_trunc('second', i.cerrado_en      at time zone v_tz),
    round((extract(epoch from (i.restablecido_en - coalesce(i.inicio_en, i.creado_en))) / 3600)::numeric, 2),
    round((extract(epoch from (pa.primera_atencion - i.creado_en)) / 3600)::numeric, 2),
    (select count(*)::int from public.reporte r where r.incidente_id = i.id),
    (select count(distinct (rs.operador_id, rs.mensaje, rs.fecha_resp))::int
       from public.respuesta rs where rs.incidente_id = i.id),
    case when re.reabierto then 'sí' else 'no' end
  from public.incidente i
  join public.servicio s       on s.id = i.servicio_id
  left join public.empresa e   on e.id = i.empresa_id
  left join public.municipio m on m.codigo_dane = i.municipio_codigo
  left join lateral (
    select min(a.creado_en) as primera_atencion
    from public.audit_log a
    where a.entidad = 'incidente' and a.entidad_id = i.id and a.accion = 'update'
      and a.despues ->> 'estado' = 'en_atencion'
      and a.antes ->> 'estado' = 'recibido'
  ) pa on true
  left join lateral (
    select exists (
      select 1 from public.audit_log a
      where a.entidad = 'incidente' and a.entidad_id = i.id and a.accion = 'update'
        and a.antes ->> 'estado' = 'restablecido' and a.despues ->> 'estado' = 'en_atencion'
    ) as reabierto
  ) re on true
  where i.creado_en >= (p_desde::timestamp at time zone v_tz)
    and i.creado_en <  ((p_hasta + 1)::timestamp at time zone v_tz)
    and (p_servicio_id is null or i.servicio_id = p_servicio_id)
    and (v_empresa is null or i.empresa_id = v_empresa)
  order by i.creado_en, i.id;

  get diagnostics v_filas = row_count;

  insert into public.audit_log (actor_id, accion, entidad, entidad_id, despues)
  values (auth.uid(), 'exportar', 'incidente', null,
          jsonb_build_object('desde', p_desde, 'hasta', p_hasta, 'servicio_id', p_servicio_id,
                             'empresa_id', v_empresa, 'filas', v_filas, 'rol', v_rol));
end;
$$;

revoke all on function public.exportar_incidentes(date, date, smallint, uuid) from public, anon;
grant execute on function public.exportar_incidentes(date, date, smallint, uuid) to authenticated;
