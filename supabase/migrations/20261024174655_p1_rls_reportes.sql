-- =====================================================================
-- SERVI-RED | Persona 1 | Fase 2, paso 3a: RLS de perfiles y reportes
-- =====================================================================

-- ¿El operador autenticado cubre este servicio en este municipio?
-- (cobertura = empresa_cobertura de su empresa)
create or replace function public.operador_cubre(p_servicio smallint, p_municipio bpchar)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.rol_actual() = 'operador'
     and exists (
       select 1 from public.empresa_cobertura c
       where c.empresa_id = public.empresa_actual()
         and c.servicio_id = p_servicio
         and c.municipio_codigo = p_municipio
     )
$$;
grant execute on function public.operador_cubre(smallint, bpchar) to authenticated;

-- ---------- perfil / ciudadano / operador ----------
-- Solo lectura desde el cliente. Las altas las hace el trigger y la
-- promoción de roles se hace desde el servidor (service_role).
create policy perfil_select on perfil for select to authenticated
using (id = (select auth.uid()) or (select public.rol_actual()) = 'admin');

create policy ciudadano_select on ciudadano for select to authenticated
using (id = (select auth.uid()) or (select public.rol_actual()) = 'admin');

create policy operador_select on operador for select to authenticated
using (
  id = (select auth.uid())
  or (select public.rol_actual()) = 'admin'
  or empresa_id = (select public.empresa_actual())
);

-- ---------- reporte ----------
-- Un ciudadano (incluida una sesión anónima) solo crea reportes propios,
-- en estado inicial y sin incidente asignado.
create policy reporte_insert on reporte for insert to authenticated
with check (
  (select public.rol_actual()) = 'ciudadano'
  and ciudadano_id = (select auth.uid())
  and estado = 'recibido'
  and incidente_id is null
);

-- Lo ve: su autor, un operador cuya empresa cubre ese servicio y municipio, y admin.
create policy reporte_select on reporte for select to authenticated
using (
  ciudadano_id = (select auth.uid())
  or (select public.rol_actual()) = 'admin'
  or public.operador_cubre(servicio_id, municipio_codigo)
);

-- Lo gestiona un operador que lo cubre (o admin)...
create policy reporte_update on reporte for update to authenticated
using (
  (select public.rol_actual()) = 'admin'
  or public.operador_cubre(servicio_id, municipio_codigo)
)
with check (
  (select public.rol_actual()) = 'admin'
  or public.operador_cubre(servicio_id, municipio_codigo)
);

-- ...pero solo puede cambiar estado e incidente (no ubicación ni descripción).
revoke update on reporte from anon, authenticated;
grant update (estado, incidente_id) on reporte to authenticated;