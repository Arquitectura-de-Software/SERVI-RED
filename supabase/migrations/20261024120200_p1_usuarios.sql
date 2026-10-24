-- =====================================================================
-- SERVI-RED | Persona 1 | Migración 3: perfiles de usuario
-- =====================================================================
-- Las credenciales las gestiona Supabase Auth (auth.users). Por eso NO se
-- guarda "password" en tablas propias (ajuste respecto al ER del SAD).
-- Tampoco se guarda "telefono" del ciudadano (minimización, req. 14).

create table perfil (
  id         uuid primary key references auth.users(id) on delete cascade,
  rol        rol_usuario not null default 'ciudadano',
  activo     boolean not null default true,
  creado_en  timestamptz not null default now()
);

-- Ciudadano: sesión anónima de Supabase (sin datos personales) con un alias
create table ciudadano (
  id             uuid primary key references perfil(id) on delete cascade,
  nombre_anonimo text not null
);

create table operador (
  id              uuid primary key references perfil(id) on delete cascade,
  empresa_id      uuid not null references empresa(id),
  nombre_completo text not null,
  cargo           text
);
create index operador_empresa_idx on operador (empresa_id);
