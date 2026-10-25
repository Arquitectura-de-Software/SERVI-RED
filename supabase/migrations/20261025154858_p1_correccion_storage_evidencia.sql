-- SERVI-RED | Persona 1 | Corrección: un ciudadano no puede leer fotos ajenas
-- apuntándolas desde su propio reporte.

drop policy evid_reportes_select on storage.objects;

create policy evid_reportes_select on storage.objects for select to authenticated
using (
  bucket_id = 'evidencias-reportes'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or (select public.rol_actual()) = 'admin'
    or (
      (select public.rol_actual()) = 'operador'
      and name in (select r.url_evidencia from public.reporte r)
    )
  )
);

-- La ruta de la evidencia debe estar en la carpeta del propio ciudadano.
-- NOT VALID: se exige en filas nuevas y no revisa las existentes, así el push
-- no falla si hay datos de prueba antiguos.
alter table public.reporte
  add constraint reporte_evidencia_en_carpeta_propia
  check (
    url_evidencia is null
    or ciudadano_id is null
    or url_evidencia like ciudadano_id::text || '/%'
  ) not valid;