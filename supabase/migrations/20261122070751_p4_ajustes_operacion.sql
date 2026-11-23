-- =====================================================================
-- SERVI-RED | Persona 4 | Ajustes de operación: reintentos, priorización,
-- respuestas a los ciudadanos y métrica de incidentes sin empresa
-- =====================================================================
-- Ajusta funciones de p4_gestion_incidentes (ya publicada, no se edita):
--   * responder y cambiar_estado_incidente aceptan client_request_id (un
--     reintento devuelve la respuesta ya creada en vez de duplicarla).
--   * responder(p_a_reportes => true) copia el mensaje a cada reporte vinculado
--     al incidente, para que cada ciudadano lo vea con la RLS respuesta_select de
--     P1 (solo ve respuestas de sus reportes). PENDIENTE de confirmar con P3
--     (app móvil): es la forma propuesta de notificar a los ciudadanos.
--   * priorizar_incidente (vista lógica 5.1: priorización).
--   * incidente_operacion: agrega prioridad_sugerida y deja de ser legible para
--     ciudadanos.
--   * metrics.incidentes_sin_empresa para el tablero de P5.
-- La columna validacion.client_request_id se crea en p4_moderacion.

-- ---------- 0. idempotencia en respuesta (tabla de P4) ----------
alter table public.respuesta add column client_request_id uuid unique;

-- ---------- 1. responder ----------
drop function if exists public.responder(text, uuid, uuid);

create function public.responder(
  p_mensaje           text,
  p_incidente_id      uuid    default null,
  p_reporte_id        uuid    default null,
  p_client_request_id uuid    default null,
  p_a_reportes        boolean default false
)
returns table (respuesta_id uuid, respondida_en timestamptz, reportes_notificados integer)
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_previa      public.respuesta%rowtype;
  v_id          uuid;
  v_fecha       timestamptz;
  v_notificados integer := 0;
begin
  if public.rol_actual() is distinct from 'operador' then
    raise exception 'Solo un operador responde' using errcode = '42501';
  end if;
  if p_incidente_id is null and p_reporte_id is null then
    raise exception 'Indique el incidente o el reporte que responde' using errcode = 'PT400';
  end if;
  if p_mensaje is null or char_length(btrim(p_mensaje)) not between 1 and 2000 then
    raise exception 'El mensaje debe tener entre 1 y 2000 caracteres' using errcode = 'PT400';
  end if;
  if coalesce(p_a_reportes, false) and (p_incidente_id is null or p_reporte_id is not null) then
    raise exception 'Para avisar a los ciudadanos indique solo el incidente' using errcode = 'PT400';
  end if;
  if p_reporte_id is not null and p_incidente_id is not null and not exists (
    select 1 from public.reporte r where r.id = p_reporte_id and r.incidente_id = p_incidente_id
  ) then
    raise exception 'El reporte no pertenece a ese incidente' using errcode = 'PT400';
  end if;

  -- Reintento: devolver la respuesta ya creada.
  if p_client_request_id is not null then
    select * into v_previa from public.respuesta rs where rs.client_request_id = p_client_request_id;
    if found then
      if v_previa.operador_id is distinct from auth.uid()
         or v_previa.incidente_id is distinct from p_incidente_id
         or v_previa.reporte_id is distinct from p_reporte_id then
        raise exception 'El client_request_id ya se usó en otra respuesta' using errcode = 'PT409';
      end if;
      return query
      select v_previa.id, v_previa.fecha_resp,
             (select count(*)::int from public.respuesta c
              where c.incidente_id = v_previa.incidente_id and c.reporte_id is not null
                and c.operador_id = v_previa.operador_id and c.mensaje = v_previa.mensaje
                and c.fecha_resp = v_previa.fecha_resp and c.id <> v_previa.id
                and v_previa.reporte_id is null);
      return;
    end if;
  end if;

  insert into public.respuesta (incidente_id, reporte_id, operador_id, mensaje, client_request_id)
  values (p_incidente_id, p_reporte_id, auth.uid(), btrim(p_mensaje), p_client_request_id)
  returning id, fecha_resp into v_id, v_fecha;

  -- Difusión: una copia por reporte vinculado, con la misma fecha (misma
  -- transacción). La línea de tiempo y el CSV la cuentan una sola vez.
  if coalesce(p_a_reportes, false) then
    insert into public.respuesta (incidente_id, reporte_id, operador_id, mensaje)
    select p_incidente_id, r.id, auth.uid(), btrim(p_mensaje)
    from public.reporte r
    where r.incidente_id = p_incidente_id
      and r.estado = 'vinculado';
    get diagnostics v_notificados = row_count;
  end if;

  return query select v_id, v_fecha, v_notificados;
end;
$$;

revoke all on function public.responder(text, uuid, uuid, uuid, boolean) from public, anon;
grant execute on function public.responder(text, uuid, uuid, uuid, boolean) to authenticated;

-- ---------- 2. cambiar estado con reintento seguro ----------
-- El cambio de estado ya era idempotente (repetir el mismo estado no hace nada);
-- con client_request_id tampoco se duplica el mensaje.
drop function if exists public.cambiar_estado_incidente(uuid, public.estado_incidente, text);

create function public.cambiar_estado_incidente(
  p_incidente_id      uuid,
  p_estado            public.estado_incidente,
  p_mensaje           text default null,
  p_client_request_id uuid default null
)
returns table (
  incidente_id     uuid,
  estado           public.estado_incidente,
  restablecido_en  timestamptz,
  cerrado_en       timestamptz,
  actualizado_en   timestamptz,
  respuesta_id     uuid
)
language plpgsql
security invoker
-- 'public' por el trigger de estados de P1 (validar_transicion_incidente),
-- que no fija su search_path. Los clientes no tienen CREATE en public.
set search_path = public, pg_temp
as $$
declare
  v_actual     public.estado_incidente;
  v_respuesta  uuid;
  v_permitidos text;
begin
  if public.rol_actual() is distinct from 'operador' and public.rol_actual() is distinct from 'admin' then
    raise exception 'Solo un operador o un administrador gestiona incidentes' using errcode = '42501';
  end if;
  if p_incidente_id is null or p_estado is null then
    raise exception 'El incidente y el estado son obligatorios' using errcode = 'PT400';
  end if;
  if p_mensaje is not null and char_length(btrim(p_mensaje)) not between 1 and 2000 then
    raise exception 'El mensaje debe tener entre 1 y 2000 caracteres' using errcode = 'PT400';
  end if;

  if not exists (select 1 from public.incidente i where i.id = p_incidente_id) then
    raise exception 'El incidente no existe' using errcode = 'PT404';
  end if;

  -- FOR UPDATE aplica también la política de UPDATE: si no lo gestiona, no hay fila.
  select i.estado into v_actual
  from public.incidente i
  where i.id = p_incidente_id
  for update;

  if not found then
    raise exception 'No gestiona este incidente' using errcode = '42501';
  end if;

  if v_actual <> p_estado then
    if not exists (select 1 from public.transicion_incidente t
                   where t.desde = v_actual and t.hacia = p_estado) then
      select string_agg(t.hacia::text, ', ' order by t.hacia) into v_permitidos
      from public.transicion_incidente t where t.desde = v_actual;
      raise exception 'Transición no permitida: % -> %', v_actual, p_estado
        using errcode = 'PT409',
              hint = 'Desde ' || v_actual || ' se puede pasar a: ' || coalesce(v_permitidos, '(ninguno)');
    end if;

    update public.incidente i set estado = p_estado where i.id = p_incidente_id;
  end if;

  if p_mensaje is not null then
    if p_client_request_id is not null then
      select rs.id into v_respuesta from public.respuesta rs
      where rs.client_request_id = p_client_request_id;
      if found and not exists (select 1 from public.respuesta rs
                               where rs.id = v_respuesta and rs.incidente_id = p_incidente_id
                                 and rs.operador_id = auth.uid()) then
        raise exception 'El client_request_id ya se usó en otra respuesta' using errcode = 'PT409';
      end if;
    end if;
    if v_respuesta is null then
      insert into public.respuesta (incidente_id, operador_id, mensaje, client_request_id)
      values (p_incidente_id, auth.uid(), btrim(p_mensaje), p_client_request_id)
      returning id into v_respuesta;
    end if;
  end if;

  return query
  select i.id, i.estado, i.restablecido_en, i.cerrado_en, i.actualizado_en, v_respuesta
  from public.incidente i where i.id = p_incidente_id;
end;
$$;

revoke all on function public.cambiar_estado_incidente(uuid, public.estado_incidente, text, uuid) from public, anon;
grant execute on function public.cambiar_estado_incidente(uuid, public.estado_incidente, text, uuid) to authenticated;

-- ---------- 3. priorizar ----------
-- 1 = más urgente, 5 = menos urgente (check de P1 en incidente.prioridad).
create or replace function public.priorizar_incidente(
  p_incidente_id uuid,
  p_prioridad    smallint
)
returns table (incidente_id uuid, prioridad smallint, actualizado_en timestamptz)
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_inc public.incidente%rowtype;
begin
  if public.rol_actual() is distinct from 'operador' and public.rol_actual() is distinct from 'admin' then
    raise exception 'Solo un operador o un administrador prioriza incidentes' using errcode = '42501';
  end if;
  if p_incidente_id is null or p_prioridad is null or p_prioridad not between 1 and 5 then
    raise exception 'La prioridad va de 1 (más urgente) a 5' using errcode = 'PT400';
  end if;

  if not exists (select 1 from public.incidente i where i.id = p_incidente_id) then
    raise exception 'El incidente no existe' using errcode = 'PT404';
  end if;

  select * into v_inc from public.incidente i where i.id = p_incidente_id for update;
  if not found then
    raise exception 'No gestiona este incidente' using errcode = '42501';
  end if;
  if v_inc.estado = 'cerrado' then
    raise exception 'Un incidente cerrado no se prioriza' using errcode = 'PT409';
  end if;

  if v_inc.prioridad is distinct from p_prioridad then
    update public.incidente i set prioridad = p_prioridad where i.id = p_incidente_id;
  end if;

  return query
  select i.id, i.prioridad, i.actualizado_en from public.incidente i where i.id = p_incidente_id;
end;
$$;

revoke all on function public.priorizar_incidente(uuid, smallint) from public, anon;
grant execute on function public.priorizar_incidente(uuid, smallint) to authenticated;

-- ---------- 4. vista del portal con prioridad sugerida ----------
-- prioridad_sugerida (1 = más urgente), solo para incidentes abiertos:
--   parte de 5 y resta
--     -1 con 3 o más reportes, -2 con 10 o más
--     -1 con 4 o más horas abierto, -2 con 12 o más
--     -1 si es energía o acueducto (servicios esenciales de mayor impacto)
--   y se limita a 1..5. Es solo una ayuda: el operador decide la prioridad real.
-- Solo operador, regulador y admin la leen (el ciudadano tiene sus propias vistas).
-- Alcance del portal: el operador ve solo los incidentes de su empresa; regulador
-- y admin ven todos. (La tabla incidente es legible para cualquier sesión por
-- decisión de P1 —no tiene datos personales—; esto acota el mapa del portal, no
-- reemplaza la RLS, que es la que impide gestionar incidentes ajenos.)
create or replace view public.incidente_operacion
with (security_invoker = true)
as
select
  i.id,
  i.servicio_id,
  s.tipo                    as servicio_tipo,
  s.descripcion             as servicio,
  i.empresa_id,
  e.nombre                  as empresa,
  i.municipio_codigo,
  m.nombre                  as municipio,
  m.departamento_codigo,
  i.estado,
  i.prioridad,
  extensions.st_y(i.centroide::extensions.geometry) as lat,
  extensions.st_x(i.centroide::extensions.geometry) as lng,
  i.operador_asignado,
  o.nombre_completo         as operador_asignado_nombre,
  i.inicio_en,
  i.restablecido_en,
  i.cerrado_en,
  i.creado_en,
  i.actualizado_en,
  rs.total_reportes,
  rs.ultimo_reporte_en,
  case when i.estado in ('recibido', 'en_atencion') then
    greatest(1, least(5,
      5
      - case when rs.total_reportes >= 10 then 2 when rs.total_reportes >= 3 then 1 else 0 end
      - case when now() - i.creado_en >= interval '12 hours' then 2
             when now() - i.creado_en >= interval '4 hours'  then 1 else 0 end
      - case when s.tipo in ('energia', 'acueducto') then 1 else 0 end
    ))::smallint
  end                       as prioridad_sugerida
from public.incidente i
join public.servicio s       on s.id = i.servicio_id
left join public.empresa e   on e.id = i.empresa_id
left join public.municipio m on m.codigo_dane = i.municipio_codigo
left join public.operador o  on o.id = i.operador_asignado
left join lateral (
  select count(*)::int as total_reportes, max(r.creado_en) as ultimo_reporte_en
  from public.reporte r
  where r.incidente_id = i.id
) rs on true
where public.rol_actual() in ('regulador', 'admin')
   or (public.rol_actual() = 'operador' and i.empresa_id = public.empresa_actual());

comment on view public.incidente_operacion is
  'P4: incidentes con lat/lng, catálogo y prioridad sugerida para el portal. Solo operador, regulador y admin; respeta la RLS.';

revoke all on public.incidente_operacion from public, anon;
grant select on public.incidente_operacion to authenticated;

-- ---------- 5. métrica: incidentes abiertos sin empresa ----------
-- Mismo patrón que las vistas metrics.* de P1: agregados sin datos personales,
-- leídos por metrics_reader (que no tiene acceso a public; por eso la vista usa
-- los permisos de su dueño, como las de P1). Si crece, la agrupación está
-- dejando incidentes sin responsable: un admin debe asignarles empresa.
create or replace view metrics.incidentes_sin_empresa as
select s.tipo::text          as servicio,
       i.municipio_codigo::text as municipio_dane,
       m.nombre              as municipio,
       count(*)::bigint      as total,
       min(i.creado_en)      as mas_antiguo
from public.incidente i
join public.servicio s       on s.id = i.servicio_id
left join public.municipio m on m.codigo_dane = i.municipio_codigo
where i.empresa_id is null
  and i.estado <> 'cerrado'
group by 1, 2, 3;

revoke all on metrics.incidentes_sin_empresa from public, anon, authenticated;
grant select on metrics.incidentes_sin_empresa to metrics_reader;
