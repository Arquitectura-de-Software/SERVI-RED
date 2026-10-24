-- =====================================================================
-- SERVI-RED | Persona 1 | Fase 2, paso 3b: RLS de incidentes y gestión
-- =====================================================================

-- ---------- transicion_incidente ----------
-- El trigger de estados consulta esta tabla con los permisos de quien actualiza,
-- así que debe poder leerse. Es información no sensible.
create policy transicion_select on transicion_incidente for select to authenticated using (true);

-- ---------- incidente ----------
-- Cualquier usuario con sesión (incluida la anónima) consulta incidentes para ver
-- el estado de su zona. No contienen datos personales.
create policy incidente_select on incidente for select to authenticated using (true);

-- Un operador crea incidentes de su empresa en servicios y municipios que cubre.
create policy incidente_insert on incidente for insert to authenticated
with check (
  (select public.rol_actual()) = 'admin'
  or (
    public.operador_cubre(servicio_id, municipio_codigo)
    and empresa_id = (select public.empresa_actual())
    and estado = 'recibido'
  )
);

-- Un operador gestiona los incidentes de su empresa (y puede asignarlos solo
-- a operadores de la misma empresa).
create policy incidente_update on incidente for update to authenticated
using (
  (select public.rol_actual()) = 'admin'
  or (public.operador_cubre(servicio_id, municipio_codigo)
      and empresa_id = (select public.empresa_actual()))
)
with check (
  (select public.rol_actual()) = 'admin'
  or (
    public.operador_cubre(servicio_id, municipio_codigo)
    and empresa_id = (select public.empresa_actual())
    and (
      operador_asignado is null
      or exists (
        select 1 from operador o
        where o.id = operador_asignado
          and o.empresa_id = (select public.empresa_actual())
      )
    )
  )
);

-- Solo estas columnas se pueden modificar desde el cliente. Las fechas de
-- restablecimiento y cierre las fija el trigger de estados.
revoke update on incidente from anon, authenticated;
grant update (estado, prioridad, operador_asignado, inicio_en) on incidente to authenticated;

-- ---------- confirmacion_ciudadana ----------
-- Un ciudadano confirma a su nombre; ve solo sus confirmaciones. Los operadores
-- ven las de incidentes de su empresa. El conteo "de la zona" lo hará una función
-- del servidor (Persona 2), no el cliente.
create policy confirmacion_insert on confirmacion_ciudadana for insert to authenticated
with check (
  (select public.rol_actual()) = 'ciudadano'
  and ciudadano_id = (select auth.uid())
);

create policy confirmacion_select on confirmacion_ciudadana for select to authenticated
using (
  ciudadano_id = (select auth.uid())
  or (select public.rol_actual()) = 'admin'
  or exists (
    select 1 from incidente i
    where i.id = confirmacion_ciudadana.incidente_id
      and i.empresa_id = (select public.empresa_actual())
  )
);

-- ---------- respuesta ----------
-- La lee el autor del reporte respondido, los operadores que lo cubren o
-- los de la empresa del incidente, y admin.
create policy respuesta_select on respuesta for select to authenticated
using (
  reporte_id in (select id from reporte)
  or (select public.rol_actual()) = 'admin'
  or exists (
    select 1 from incidente i
    where i.id = respuesta.incidente_id
      and i.empresa_id = (select public.empresa_actual())
  )
);

-- Solo un operador responde, a su nombre, sobre reportes que cubre o incidentes de su empresa.
create policy respuesta_insert on respuesta for insert to authenticated
with check (
  (select public.rol_actual()) = 'operador'
  and operador_id = (select auth.uid())
  and (
    reporte_id in (select id from reporte)
    or exists (
      select 1 from incidente i
      where i.id = respuesta.incidente_id
        and i.empresa_id = (select public.empresa_actual())
    )
  )
);