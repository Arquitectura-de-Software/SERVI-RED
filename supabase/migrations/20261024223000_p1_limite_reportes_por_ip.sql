-- SERVI-RED | Persona 1 | Fase 4: límite de reportes por IP

insert into private.rate_limit_policy (operacion, ventana_segundos, max_solicitudes)
values
  ('reporte_ip', 60, 20),
  ('reporte_ip', 86400, 100);

create or replace function private.aplicar_limite_reporte()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_ip inet;
begin
  v_uid := auth.uid();
  if v_uid is not null and public.rol_actual() = 'ciudadano' then
    v_ip := private.ip_solicitante_actual();
    perform private.consumir_limite('reporte_usuario', v_uid::text, 60, 5);
    perform private.consumir_limite('reporte_usuario', v_uid::text, 86400, 30);
    perform private.consumir_limite('reporte_ip', v_ip::text, 60, 20);
    perform private.consumir_limite('reporte_ip', v_ip::text, 86400, 100);
  end if;
  return new;
end;
$$;

revoke all on function private.aplicar_limite_reporte() from public, anon, authenticated;

update private.rate_limit_policy
set operacion = 'reporte_usuario'
where operacion = 'reporte';
