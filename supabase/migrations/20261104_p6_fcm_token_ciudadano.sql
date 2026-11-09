// Migración: agrega la columna fcm_token a ciudadano para soportar notificaciones push.
-- La columna es nullable porque el token solo existe si el usuario otorgó el permiso.
-- Un trigger de Supabase Realtime en esta tabla no es necesario:
-- el token lo actualiza el cliente Android tras cada inicio de sesión o refresh de FCM.

alter table public.ciudadano
  add column if not exists fcm_token text;

comment on column public.ciudadano.fcm_token is
  'Token FCM del dispositivo. Nullable: solo presente si el usuario aceptó notificaciones.';

-- RLS: solo el propio ciudadano puede actualizar su token
create policy "ciudadano_actualizar_fcm_token"
  on public.ciudadano
  for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

