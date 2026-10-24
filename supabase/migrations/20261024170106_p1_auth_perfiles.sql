-- =====================================================================
-- SERVI-RED | Persona 1 | Fase 2, paso 1: perfiles automáticos y helpers de rol
-- =====================================================================

-- Al crearse un usuario en Supabase Auth (incluidas las sesiones anónimas)
-- se crea su perfil como "ciudadano". El rol NUNCA se toma de datos que envíe
-- el cliente: operadores y reguladores se promueven solo desde el servidor.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.perfil (id, rol) values (new.id, 'ciudadano');
  insert into public.ciudadano (id, nombre_anonimo)
  values (new.id, 'Ciudadano-' || substr(new.id::text, 1, 8));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Rol del usuario autenticado (null si no hay sesión o el perfil está inactivo)
create or replace function public.rol_actual()
returns public.rol_usuario
language sql
stable
security definer
set search_path = ''
as $$
  select p.rol from public.perfil p
  where p.id = (select auth.uid()) and p.activo
$$;

-- Empresa a la que pertenece el operador autenticado (null si no es operador)
create or replace function public.empresa_actual()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select o.empresa_id from public.operador o
  where o.id = (select auth.uid())
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;
grant execute on function public.rol_actual()     to anon, authenticated;
grant execute on function public.empresa_actual() to anon, authenticated;