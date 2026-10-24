-- =====================================================================
-- SERVI-RED | Persona 1 | Migración 5: auditoría, outbox y estados
-- =====================================================================

-- Auditoría de acciones de operadores e institucionales (req. 19)
create table audit_log (
  id              bigint generated always as identity primary key,
  actor_id        uuid,
  accion          text not null,
  entidad         text not null,
  entidad_id      uuid,
  antes           jsonb,
  despues         jsonb,
  correlation_id  uuid,
  creado_en       timestamptz not null default now()
);
create index audit_log_entidad_idx on audit_log (entidad, entidad_id);
create index audit_log_actor_idx on audit_log (actor_id, creado_en desc);

-- Outbox de eventos asíncronos (ADR-03). Los triggers/consumidores se
-- construyen en la Fase 3.
create table evento_outbox (
  id                bigint generated always as identity primary key,
  tipo              text not null,
  payload           jsonb not null default '{}'::jsonb,
  estado            estado_evento not null default 'pendiente',
  intentos          int not null default 0,
  siguiente_intento timestamptz not null default now(),
  ultimo_error      text,
  correlation_id    uuid not null default gen_random_uuid(),
  creado_en         timestamptz not null default now(),
  procesado_en      timestamptz
);
create index evento_outbox_cola_idx on evento_outbox (siguiente_intento)
  where estado in ('pendiente', 'fallido');

-- Máquina de estados del incidente (req. 20)
create table transicion_incidente (
  desde  estado_incidente not null,
  hacia  estado_incidente not null,
  primary key (desde, hacia)
);
insert into transicion_incidente (desde, hacia) values
  ('recibido',     'en_atencion'),
  ('recibido',     'cerrado'),        -- descartar un incidente falso
  ('en_atencion',  'restablecido'),
  ('restablecido', 'cerrado'),
  ('restablecido', 'en_atencion');    -- reabrir si los ciudadanos siguen sin servicio

create or replace function validar_transicion_incidente()
returns trigger
language plpgsql
as $$
begin
  if new.estado is distinct from old.estado then
    if not exists (
      select 1 from transicion_incidente t
      where t.desde = old.estado and t.hacia = new.estado
    ) then
      raise exception 'Transición de estado no permitida: % -> %', old.estado, new.estado
        using errcode = 'check_violation';
    end if;

    if new.estado = 'restablecido' then
      new.restablecido_en := coalesce(new.restablecido_en, now());
    elsif new.estado = 'cerrado' then
      new.cerrado_en := coalesce(new.cerrado_en, now());
    elsif new.estado = 'en_atencion' and old.estado = 'restablecido' then
      new.restablecido_en := null;
    end if;
  end if;

  new.actualizado_en := now();
  return new;
end;
$$;

create trigger trg_incidente_transicion
  before update on incidente
  for each row execute function validar_transicion_incidente();
