-- SERVI-RED | Persona 1 | Fase 3: contrato de eventos y entrega del outbox

alter table public.evento_outbox
  add column lease_token uuid,
  add column bloqueado_hasta timestamptz,
  add constraint evento_outbox_lease_consistente
    check ((lease_token is null) = (bloqueado_hasta is null));

create index evento_outbox_pendiente_idx
  on public.evento_outbox (siguiente_intento, bloqueado_hasta, creado_en)
  where estado = 'pendiente';

-- Payloads mínimos: nunca se incluyen datos del ciudadano, descripción,
-- ubicación, evidencia ni códigos/hash de seguimiento.
create or replace function public.encolar_evento_outbox()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tipo text;
  v_payload jsonb;
begin
  if tg_table_name = 'reporte' and tg_op = 'INSERT' then
    v_tipo := 'reporte.creado';
    v_payload := jsonb_build_object(
      'reporte_id', new.id,
      'servicio_id', new.servicio_id,
      'municipio_codigo', new.municipio_codigo,
      'creado_en', new.creado_en
    );
  elsif tg_table_name = 'reporte'
        and tg_op = 'UPDATE'
        and new.estado is distinct from old.estado then
    v_tipo := 'reporte.estado_cambiado';
    v_payload := jsonb_build_object(
      'reporte_id', new.id,
      'estado_anterior', old.estado,
      'estado_nuevo', new.estado,
      'incidente_id', new.incidente_id
    );
  elsif tg_table_name = 'incidente'
        and tg_op = 'UPDATE'
        and new.estado is distinct from old.estado then
    v_tipo := 'incidente.estado_cambiado';
    v_payload := jsonb_build_object(
      'incidente_id', new.id,
      'servicio_id', new.servicio_id,
      'municipio_codigo', new.municipio_codigo,
      'estado_anterior', old.estado,
      'estado_nuevo', new.estado,
      'cambiado_en', new.actualizado_en
    );
  elsif tg_table_name = 'denuncia'
        and tg_op = 'UPDATE'
        and new.estado is distinct from old.estado then
    v_tipo := 'denuncia.estado_cambiado';
    v_payload := jsonb_build_object(
      'denuncia_id', new.id,
      'servicio_id', new.servicio_id,
      'municipio_codigo', new.municipio_codigo,
      'estado_anterior', old.estado,
      'estado_nuevo', new.estado,
      'cambiado_en', now()
    );
  else
    return new;
  end if;

  insert into public.evento_outbox (tipo, payload)
  values (v_tipo, v_payload);

  return new;
end;
$$;

revoke all on function public.encolar_evento_outbox() from public, anon, authenticated;

create trigger outbox_reporte_creado
  after insert on public.reporte
  for each row execute function public.encolar_evento_outbox();

create trigger outbox_reporte_estado
  after update of estado on public.reporte
  for each row execute function public.encolar_evento_outbox();

create trigger outbox_incidente_estado
  after update of estado on public.incidente
  for each row execute function public.encolar_evento_outbox();

create trigger outbox_denuncia_estado
  after update of estado on public.denuncia
  for each row execute function public.encolar_evento_outbox();

-- Una reclamación incrementa intentos y fija un lease. Si el consumidor cae,
-- el evento vuelve a estar disponible cuando expire el lease.
create or replace function public.reclamar_eventos_outbox(
  p_limite integer default 50,
  p_lease_segundos integer default 300
)
returns table (
  id bigint,
  tipo text,
  payload jsonb,
  intentos integer,
  correlation_id uuid,
  lease_token uuid,
  lease_hasta timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_limite is null or p_limite < 1 or p_limite > 100 then
    raise exception 'El límite debe estar entre 1 y 100' using errcode = '22023';
  end if;
  if p_lease_segundos is null or p_lease_segundos < 30 or p_lease_segundos > 900 then
    raise exception 'El lease debe estar entre 30 y 900 segundos' using errcode = '22023';
  end if;

  update public.evento_outbox e
  set estado = 'fallido',
      lease_token = null,
      bloqueado_hasta = null,
      ultimo_error = coalesce(e.ultimo_error, 'Se agotaron los intentos tras expirar el lease')
  where e.estado = 'pendiente'
    and e.intentos >= 5
    and e.bloqueado_hasta <= now();

  return query
  with candidatos as (
    select e.id
    from public.evento_outbox e
    where e.estado = 'pendiente'
      and e.siguiente_intento <= now()
      and (e.bloqueado_hasta is null or e.bloqueado_hasta <= now())
      and e.intentos < 5
    order by e.siguiente_intento, e.creado_en, e.id
    for update skip locked
    limit p_limite
  )
  update public.evento_outbox e
  set intentos = e.intentos + 1,
      lease_token = gen_random_uuid(),
      bloqueado_hasta = now() + make_interval(secs => p_lease_segundos)
  from candidatos c
  where e.id = c.id
  returning e.id, e.tipo, e.payload, e.intentos, e.correlation_id,
            e.lease_token, e.bloqueado_hasta;
end;
$$;

create or replace function public.marcar_evento_outbox_procesado(
  p_id bigint,
  p_lease_token uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.evento_outbox e
  set estado = 'procesado',
      procesado_en = now(),
      ultimo_error = null,
      lease_token = null,
      bloqueado_hasta = null
  where e.id = p_id
    and e.estado = 'pendiente'
    and e.lease_token = p_lease_token;

  if not found then
    raise exception 'Evento inexistente o lease vencido para id %', p_id
      using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.registrar_fallo_evento_outbox(
  p_id bigint,
  p_lease_token uuid,
  p_error text
)
returns public.estado_evento
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_intentos integer;
  v_estado public.estado_evento;
begin
  if p_error is null or length(btrim(p_error)) = 0 then
    raise exception 'El detalle del fallo es obligatorio' using errcode = '22023';
  end if;

  select e.intentos into v_intentos
  from public.evento_outbox e
  where e.id = p_id
    and e.estado = 'pendiente'
    and e.lease_token = p_lease_token
  for update;

  if not found then
    raise exception 'Evento inexistente o lease vencido para id %', p_id
      using errcode = 'P0002';
  end if;

  v_estado := case when v_intentos >= 5 then 'fallido'::public.estado_evento
                   else 'pendiente'::public.estado_evento end;

  update public.evento_outbox e
  set estado = v_estado,
      siguiente_intento = case
        when v_estado = 'pendiente' then
          now() + make_interval(secs => least(900, 15 * (2 ^ (v_intentos - 1))::integer))
        else e.siguiente_intento
      end,
      ultimo_error = left(btrim(p_error), 1000),
      lease_token = null,
      bloqueado_hasta = null
  where e.id = p_id;

  return v_estado;
end;
$$;

revoke all on function public.reclamar_eventos_outbox(integer, integer) from public, anon, authenticated;
revoke all on function public.marcar_evento_outbox_procesado(bigint, uuid) from public, anon, authenticated;
revoke all on function public.registrar_fallo_evento_outbox(bigint, uuid, text) from public, anon, authenticated;

grant execute on function public.reclamar_eventos_outbox(integer, integer) to service_role;
grant execute on function public.marcar_evento_outbox_procesado(bigint, uuid) to service_role;
grant execute on function public.registrar_fallo_evento_outbox(bigint, uuid, text) to service_role;
