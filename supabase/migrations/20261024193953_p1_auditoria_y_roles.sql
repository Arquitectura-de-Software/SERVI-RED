-- =====================================================================
-- SERVI-RED | Persona 1 | Fase 2, paso 3d: tablas restantes, auditoría y promoción de roles
-- =====================================================================

-- ---------- indicador ----------
-- Consolidados: los leen operadores, reguladores y admin (no ciudadanos).
-- Las escrituras las hacen trabajos del servidor (service_role), sin política.
create policy indicador_select on indicador for select to authenticated
using ((select public.rol_actual()) in ('operador', 'regulador', 'admin'));

-- ---------- evento_outbox ----------
-- Solo el servidor (service_role) la usa. Se cierra todo acceso desde el cliente.
revoke all on evento_outbox from anon, authenticated;

-- ---------- audit_log ----------
-- Solo admin lee la auditoría. Nadie escribe desde el cliente: la escriben los
-- triggers de abajo.
revoke all on audit_log from anon, authenticated;
grant select on audit_log to authenticated;

create policy audit_select on audit_log for select to authenticated
using ((select public.rol_actual()) = 'admin');

-- Trigger genérico de auditoría (req. 19). Nunca guarda el hash de seguimiento
-- de las denuncias.
create or replace function public.auditar_cambio()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if tg_op = 'DELETE' then v_id := old.id; else v_id := new.id; end if;

  insert into public.audit_log (actor_id, accion, entidad, entidad_id, antes, despues)
  values (
    (select auth.uid()),
    lower(tg_op),
    tg_table_name,
    v_id,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) - 'seguimiento_hash' end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) - 'seguimiento_hash' end
  );
  return null;
end;
$$;
revoke execute on function public.auditar_cambio() from public, anon, authenticated;

create trigger aud_incidente after insert or update on incidente
  for each row execute function public.auditar_cambio();
create trigger aud_validacion after insert or update on validacion
  for each row execute function public.auditar_cambio();
create trigger aud_respuesta after insert on respuesta
  for each row execute function public.auditar_cambio();
create trigger aud_reporte after update on reporte
  for each row execute function public.auditar_cambio();
create trigger aud_denuncia after update on denuncia
  for each row execute function public.auditar_cambio();

-- ---------- promoción de roles ----------
-- Convierte a un usuario existente en operador, regulador o admin. Solo la puede
-- ejecutar el servidor (service_role / SQL Editor), nunca un cliente.
create or replace function public.promover_usuario(
  p_user_id         uuid,
  p_rol             public.rol_usuario,
  p_empresa_id      uuid default null,
  p_nombre_completo text default null,
  p_cargo           text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_rol = 'operador' and (p_empresa_id is null or p_nombre_completo is null) then
    raise exception 'Un operador requiere empresa y nombre completo' using errcode = '22023';
  end if;

  update public.perfil set rol = p_rol where id = p_user_id;
  if not found then
    raise exception 'El usuario no existe' using errcode = '22023';
  end if;

  if p_rol = 'operador' then
    insert into public.operador (id, empresa_id, nombre_completo, cargo)
    values (p_user_id, p_empresa_id, p_nombre_completo, p_cargo)
    on conflict (id) do update
      set empresa_id = excluded.empresa_id,
          nombre_completo = excluded.nombre_completo,
          cargo = excluded.cargo;
  else
    delete from public.operador where id = p_user_id;
  end if;
end;
$$;

revoke execute on function public.promover_usuario(uuid, public.rol_usuario, uuid, text, text) from public, anon, authenticated;
grant execute on function public.promover_usuario(uuid, public.rol_usuario, uuid, text, text) to service_role;