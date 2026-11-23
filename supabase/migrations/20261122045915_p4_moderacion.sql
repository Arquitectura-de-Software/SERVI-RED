-- =====================================================================
-- SERVI-RED | Persona 4 | Moderación de denuncias y reportes
-- =====================================================================
-- Cada decisión de moderación registra una fila en `validacion` y cambia el
-- estado de la denuncia o del reporte en la MISMA transacción: no puede quedar
-- una validación sin su efecto ni un cambio de estado sin quién lo decidió.
-- `validacion` funciona como historial (se inserta; no se reescribe).
--
-- Decisión -> efecto:
--   denuncia  pendiente -> en_revision | aprobada -> validada | rechazada -> descartada
--   reporte   aprobada  -> sin cambio de estado | rechazada -> descartado y se
--             desvincula del incidente (se recalcula el centroide; si el incidente
--             queda sin reportes y seguía en 'recibido', se cierra)
-- Rechazar exige comentario (motivo), para la trazabilidad (req. 19).
-- Solo modera un operador: validacion.operador_id referencia a operador.
--
-- Reintentos (red móvil, doble clic): cada decisión acepta un client_request_id
-- opcional. Si ya existe una validación con ese id para la misma denuncia o
-- reporte, se devuelve esa en vez de fallar con 409 por "ya moderada".
-- Correlation ID: las funciones security definer llaman a
-- private.correlation_id_actual(); en las invoker lo asigna el trigger de
-- audit_log de P1 (los clientes no tienen permiso sobre el esquema private).

-- ---------- 0. idempotencia ----------
-- validacion es tabla de P4 (README).
alter table public.validacion add column client_request_id uuid unique;

-- ---------- 1. moderar denuncia ----------
-- Con los permisos de quien llama: RLS denuncia_update y validacion_insert de P1.
create or replace function public.moderar_denuncia(
  p_denuncia_id uuid,
  p_decision    public.estado_validacion,
  p_comentario  text default null,
  p_client_request_id uuid default null
)
returns table (
  validacion_id    uuid,
  denuncia_id      uuid,
  estado_denuncia  public.estado_denuncia
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_actual     public.estado_denuncia;
  v_nuevo      public.estado_denuncia;
  v_validacion uuid;
begin
  if public.rol_actual() is distinct from 'operador' then
    raise exception 'Solo un operador modera denuncias' using errcode = '42501';
  end if;
  if p_denuncia_id is null or p_decision is null then
    raise exception 'La denuncia y la decisión son obligatorias' using errcode = 'PT400';
  end if;
  if p_comentario is not null and char_length(btrim(p_comentario)) not between 1 and 2000 then
    raise exception 'El comentario debe tener entre 1 y 2000 caracteres' using errcode = 'PT400';
  end if;
  if p_decision = 'rechazada' and nullif(btrim(p_comentario), '') is null then
    raise exception 'Para rechazar hay que indicar el motivo' using errcode = 'PT400';
  end if;

  -- RLS: si no la cubre, no la ve (no se distingue "no existe" de "no es suya",
  -- para no revelar denuncias de otras zonas).
  select d.estado into v_actual
  from public.denuncia d
  where d.id = p_denuncia_id
  for update;
  if not found then
    raise exception 'La denuncia no existe o no está en su zona' using errcode = 'PT404';
  end if;

  -- Reintento: la denuncia ya está bloqueada, así que dos reintentos simultáneos
  -- se atienden en orden y el segundo encuentra la validación del primero.
  if p_client_request_id is not null then
    select v.id into v_validacion
    from public.validacion v
    where v.client_request_id = p_client_request_id;
    if found then
      if not exists (select 1 from public.validacion v
                     where v.id = v_validacion and v.denuncia_id = p_denuncia_id) then
        raise exception 'El client_request_id ya se usó en otra decisión' using errcode = 'PT409';
      end if;
      return query select v_validacion, p_denuncia_id, v_actual;
      return;
    end if;
  end if;

  if v_actual in ('validada', 'descartada') then
    raise exception 'La denuncia ya fue moderada (%)', v_actual using errcode = 'PT409';
  end if;

  v_nuevo := case p_decision
               when 'pendiente' then 'en_revision'
               when 'aprobada'  then 'validada'
               when 'rechazada' then 'descartada'
             end::public.estado_denuncia;

  insert into public.validacion (denuncia_id, operador_id, estado, comentario, client_request_id)
  values (p_denuncia_id, auth.uid(), p_decision, nullif(btrim(p_comentario), ''), p_client_request_id)
  returning id into v_validacion;

  if v_nuevo is distinct from v_actual then
    update public.denuncia d set estado = v_nuevo where d.id = p_denuncia_id;
  end if;

  return query select v_validacion, p_denuncia_id, v_nuevo;
end;
$$;

revoke all on function public.moderar_denuncia(uuid, public.estado_validacion, text, uuid) from public, anon;
grant execute on function public.moderar_denuncia(uuid, public.estado_validacion, text, uuid) to authenticated;

-- ---------- 2. moderar reporte ----------
-- security definer: al rechazar hay que recalcular el centroide (columna que el
-- cliente no puede editar). Repite la condición de la RLS reporte_update de P1.
-- search_path = public, pg_temp por el trigger de estados de P1 (ver
-- p4_gestion_incidentes); los clientes no tienen CREATE en public.
create or replace function public.moderar_reporte(
  p_reporte_id uuid,
  p_decision   public.estado_validacion,
  p_comentario text default null,
  p_client_request_id uuid default null
)
returns table (
  validacion_id      uuid,
  reporte_id         uuid,
  estado_reporte     public.estado_reporte,
  incidente_id       uuid,
  incidente_cerrado  boolean
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_rep         public.reporte%rowtype;
  v_validacion  uuid;
  v_restantes   integer;
  v_cerrado     boolean := false;
  v_previa      public.validacion%rowtype;
  v_inc_previo  uuid;
begin
  perform private.correlation_id_actual();
  if public.rol_actual() is distinct from 'operador' then
    raise exception 'Solo un operador modera reportes' using errcode = '42501';
  end if;
  if p_reporte_id is null or p_decision is null then
    raise exception 'El reporte y la decisión son obligatorios' using errcode = 'PT400';
  end if;
  if p_decision = 'pendiente' then
    raise exception 'Un reporte se aprueba o se rechaza' using errcode = 'PT400';
  end if;
  if p_comentario is not null and char_length(btrim(p_comentario)) not between 1 and 2000 then
    raise exception 'El comentario debe tener entre 1 y 2000 caracteres' using errcode = 'PT400';
  end if;
  if p_decision = 'rechazada' and nullif(btrim(p_comentario), '') is null then
    raise exception 'Para rechazar hay que indicar el motivo' using errcode = 'PT400';
  end if;

  select * into v_rep from public.reporte r where r.id = p_reporte_id for update;
  if not found or not public.operador_cubre(v_rep.servicio_id, v_rep.municipio_codigo) then
    raise exception 'El reporte no existe o no está en su zona' using errcode = 'PT404';
  end if;

  -- Reintento: se devuelve la decisión ya registrada (el reporte está bloqueado).
  if p_client_request_id is not null then
    select * into v_previa from public.validacion v where v.client_request_id = p_client_request_id;
    if found then
      if v_previa.reporte_id is distinct from p_reporte_id or v_previa.operador_id is distinct from auth.uid() then
        raise exception 'El client_request_id ya se usó en otra decisión' using errcode = 'PT409';
      end if;
      -- Si se rechazó, el incidente del que salió está en la auditoría del reporte.
      select (a.antes ->> 'incidente_id')::uuid into v_inc_previo
      from public.audit_log a
      where a.entidad = 'reporte' and a.entidad_id = p_reporte_id and a.accion = 'update'
        and a.antes ->> 'incidente_id' is not null and a.despues ->> 'incidente_id' is null
      order by a.id desc
      limit 1;
      v_inc_previo := coalesce(v_rep.incidente_id, v_inc_previo);
      return query
      select v_previa.id, v_rep.id, v_rep.estado, v_inc_previo,
             exists (select 1 from public.incidente i
                     where i.id = v_inc_previo and i.estado = 'cerrado'
                       and not exists (select 1 from public.reporte r where r.incidente_id = i.id));
      return;
    end if;
  end if;

  if v_rep.estado = 'descartado' then
    raise exception 'El reporte ya fue descartado' using errcode = 'PT409';
  end if;

  insert into public.validacion (reporte_id, operador_id, estado, comentario, client_request_id)
  values (p_reporte_id, auth.uid(), p_decision, nullif(btrim(p_comentario), ''), p_client_request_id)
  returning id into v_validacion;

  if p_decision = 'rechazada' then
    update public.reporte r
       set estado = 'descartado', incidente_id = null
     where r.id = p_reporte_id;

    if v_rep.incidente_id is not null then
      perform 1 from public.incidente i where i.id = v_rep.incidente_id for update;

      select count(*) into v_restantes
      from public.reporte r where r.incidente_id = v_rep.incidente_id;

      if v_restantes > 0 then
        update public.incidente i
           set centroide = (
                 select extensions.st_centroid(
                          extensions.st_collect(r.ubicacion::extensions.geometry)
                        )::extensions.geography
                 from public.reporte r
                 where r.incidente_id = v_rep.incidente_id)
         where i.id = v_rep.incidente_id;
      else
        -- Incidente sin reportes: si nadie lo había empezado a atender, era falso.
        update public.incidente i
           set estado = 'cerrado'
         where i.id = v_rep.incidente_id
           and i.estado = 'recibido';
        v_cerrado := found;
      end if;
    end if;
  end if;

  return query
  select v_validacion, r.id, r.estado, v_rep.incidente_id, v_cerrado
  from public.reporte r where r.id = p_reporte_id;
end;
$$;

revoke all on function public.moderar_reporte(uuid, public.estado_validacion, text, uuid) from public, anon;
grant execute on function public.moderar_reporte(uuid, public.estado_validacion, text, uuid) to authenticated;

-- ---------- 3. cola de moderación ----------
-- security_invoker: el operador ve solo lo de su cobertura (RLS de P1).
-- Nunca expone seguimiento_hash ni ciudadano_id.
--   denuncias: 'recibida' o 'en_revision'
--   reportes:  no descartados y sin ninguna validación todavía
create or replace view public.cola_moderacion
with (security_invoker = true)
as
select
  'denuncia'::text          as tipo,
  d.id,
  d.servicio_id,
  s.tipo                    as servicio_tipo,
  d.municipio_codigo,
  m.nombre                  as municipio,
  d.estado::text            as estado,
  d.descripcion,
  d.url_evidencia,
  extensions.st_y(d.ubicacion_aprox::extensions.geometry) as lat,
  extensions.st_x(d.ubicacion_aprox::extensions.geometry) as lng,
  null::uuid                as incidente_id,
  d.creada_en               as creado_en,
  uv.estado                 as ultima_decision,
  uv.comentario             as ultimo_comentario,
  uv.fecha                  as ultima_decision_en
from public.denuncia d
join public.servicio s       on s.id = d.servicio_id
left join public.municipio m on m.codigo_dane = d.municipio_codigo
left join lateral (
  select v.estado, v.comentario, v.fecha
  from public.validacion v
  where v.denuncia_id = d.id
  order by v.fecha desc
  limit 1
) uv on true
where d.estado in ('recibida', 'en_revision')

union all

select
  'reporte'::text,
  r.id,
  r.servicio_id,
  s.tipo,
  r.municipio_codigo,
  m.nombre,
  r.estado::text,
  r.descripcion,
  r.url_evidencia,
  extensions.st_y(r.ubicacion::extensions.geometry),
  extensions.st_x(r.ubicacion::extensions.geometry),
  r.incidente_id,
  r.creado_en,
  null::public.estado_validacion,
  null::text,
  null::timestamptz
from public.reporte r
join public.servicio s       on s.id = r.servicio_id
left join public.municipio m on m.codigo_dane = r.municipio_codigo
where r.estado <> 'descartado'
  and not exists (select 1 from public.validacion v where v.reporte_id = r.id);

comment on view public.cola_moderacion is
  'P4: denuncias y reportes pendientes de moderación para el portal del operador. Respeta la RLS.';

revoke all on public.cola_moderacion from public, anon;
grant select on public.cola_moderacion to authenticated;
