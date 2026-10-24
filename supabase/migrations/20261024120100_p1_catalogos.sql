-- =====================================================================
-- SERVI-RED | Persona 1 | Migración 2: catálogos territoriales y de servicio
-- =====================================================================

create table departamento (
  codigo_dane  char(2) primary key,
  nombre       text not null
);

create table municipio (
  codigo_dane           char(5) primary key,
  departamento_codigo   char(2) not null references departamento(codigo_dane),
  nombre                text not null,
  geom                  extensions.geometry(MultiPolygon, 4326)   -- polígono municipal (se carga después)
);
create index municipio_departamento_idx on municipio (departamento_codigo);
create index municipio_geom_gix on municipio using gist (geom);

create table codigo_postal (
  codigo            text primary key,
  municipio_codigo  char(5) references municipio(codigo_dane)
);

create table empresa (
  id            uuid primary key default gen_random_uuid(),
  nombre        text not null,
  nit           text not null unique,
  tipo_entidad  text not null,
  creada_en     timestamptz not null default now()
);

create table servicio (
  id           smallint generated always as identity primary key,
  tipo         tipo_servicio not null unique,
  descripcion  text
);

-- Qué empresa presta qué servicio en qué municipio (zona de operación)
create table empresa_cobertura (
  empresa_id        uuid not null references empresa(id) on delete cascade,
  servicio_id       smallint not null references servicio(id),
  municipio_codigo  char(5) not null references municipio(codigo_dane),
  primary key (empresa_id, servicio_id, municipio_codigo)
);
create index empresa_cobertura_municipio_idx on empresa_cobertura (municipio_codigo, servicio_id);
