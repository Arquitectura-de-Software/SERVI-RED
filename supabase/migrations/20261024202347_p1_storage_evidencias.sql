-- =====================================================================
-- SERVI-RED | Persona 1 | Fase 2, paso 13: Storage para evidencias
-- =====================================================================

-- Buckets privados: solo JPEG/PNG/WebP, máximo 5 MB
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('evidencias-reportes',  'evidencias-reportes',  false, 5242880,
   array['image/jpeg', 'image/png', 'image/webp']),
  ('evidencias-denuncias', 'evidencias-denuncias', false, 5242880,
   array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ---------- evidencias de reportes ----------
-- Ruta obligatoria: <uuid_del_ciudadano>/<archivo>. Cada ciudadano solo sube
-- a su propia carpeta.
create policy evid_reportes_insert on storage.objects for insert to authenticated
with check (
  bucket_id = 'evidencias-reportes'
  and (select public.rol_actual()) = 'ciudadano'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

-- Lo lee su autor (carpeta propia), admin, o quien pueda ver un reporte que
-- apunte a ese archivo (la RLS de reporte ya limita a operadores por cobertura).
-- reporte.url_evidencia debe guardar la ruta exacta del objeto.
create policy evid_reportes_select on storage.objects for select to authenticated
using (
  bucket_id = 'evidencias-reportes'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or (select public.rol_actual()) = 'admin'
    or name in (select r.url_evidencia from public.reporte r)
  )
);

-- ---------- evidencias de denuncias ----------
-- Sin carpeta por usuario (identificaría al denunciante): nombre plano y
-- aleatorio. Basta una sesión anónima para subir.
create policy evid_denuncias_insert on storage.objects for insert to authenticated
with check (
  bucket_id = 'evidencias-denuncias'
  and (select public.rol_actual()) = 'ciudadano'
  and position('/' in name) = 0
);

-- Solo admin u operadores que cubren la denuncia que apunta al archivo
-- (la RLS de denuncia ya lo filtra). Ningún ciudadano lee estas fotos.
create policy evid_denuncias_select on storage.objects for select to authenticated
using (
  bucket_id = 'evidencias-denuncias'
  and (
    (select public.rol_actual()) = 'admin'
    or name in (select d.url_evidencia from public.denuncia d)
  )
);