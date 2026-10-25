-- SERVI-RED | Persona 1 | Fase 5b: mejoras agrupadas de las Fases 3 y 4

-- ---------- 1. evento denuncia.creada ----------
-- Misma función de la Fase 3, con una rama nueva. Nunca incluye hash ni texto.
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
  elsif tg_table_name = 'denuncia' and tg_op = 'INSERT' then
    v_tipo := 'denuncia.creada';
    v_payload := jsonb_build_object(
      'denuncia_id', new.id,
      'servicio_id', new.servicio_id,
      'municipio_codigo', new.municipio_codigo,
      'creado_en', new.creada_en
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

create trigger outbox_denuncia_creada
  after insert on public.denuncia
  for each row execute function public.encolar_evento_outbox();

-- ---------- 2. límite por IP de reportes más holgado ----------
-- Muchos usuarios móviles comparten IP (CGNAT); el límite por usuario sigue igual.
-- consumir_limite() usa esta tabla y solo recurre a los valores del código si
-- no hay fila de política.
update private.rate_limit_policy set max_solicitudes = 60
 where operacion = 'reporte_ip' and ventana_segundos = 60;
update private.rate_limit_policy set max_solicitudes = 1000
 where operacion = 'reporte_ip' and ventana_segundos = 86400;

-- ---------- 3. limpieza del outbox ----------
create or replace function private.limpiar_outbox()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.evento_outbox
  where estado = 'procesado' and procesado_en < now() - interval '7 days';

  delete from public.evento_outbox
  where estado = 'fallido' and creado_en < now() - interval '30 days';
end;
$$;
revoke all on function private.limpiar_outbox() from public, anon, authenticated;

-- pg_cron: si no se puede activar, la migración no falla; solo avisa.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    begin
      create extension if not exists pg_cron with schema pg_catalog;
      perform cron.schedule('limpiar-outbox', '17 3 * * *', 'select private.limpiar_outbox()');
    exception when others then
      raise notice 'No se pudo configurar pg_cron (%). Programar private.limpiar_outbox() a mano.', sqlerrm;
    end;
  else
    raise notice 'pg_cron no está disponible. Programar private.limpiar_outbox() a mano.';
  end if;
end $$;

-- ---------- 4. reencolar un evento fallido ----------
create or replace function public.reintentar_evento_outbox(p_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.evento_outbox e
  set estado = 'pendiente',
      intentos = 0,
      siguiente_intento = now(),
      ultimo_error = null,
      procesado_en = null,
      lease_token = null,
      bloqueado_hasta = null
  where e.id = p_id and e.estado = 'fallido';

  if not found then
    raise exception 'Evento inexistente o no está en estado fallido: %', p_id
      using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.reintentar_evento_outbox(bigint) from public, anon, authenticated;
grant execute on function public.reintentar_evento_outbox(bigint) to service_role;