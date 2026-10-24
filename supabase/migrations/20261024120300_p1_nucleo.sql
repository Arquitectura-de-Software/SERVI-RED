-- =====================================================================
-- SERVI-RED | Persona 1 | Migración 4: reportes, incidentes y gestión
-- =====================================================================

-- Incidente: la interrupción real que agrupa varios reportes
create table incidente (
  id                 uuid primary key default gen_random_uuid(),
  servicio_id        smallint not null references servicio(id),
  empresa_id         uuid references empresa(id),
  municipio_codigo   char(5) references municipio(codigo_dane),
  centroide          geography(Point, 4326),
  estado             estado_incidente not null default 'recibido',
  prioridad          smallint not null default 3 check (prioridad between 1 and 5),
  operador_asignado  uuid references operador(id),
  inicio_en          timestamptz,
  restablecido_en    timestamptz,
  cerrado_en         timestamptz,
  creado_en          timestamptz not null default now(),
  actualizado_en     timestamptz not null default now()
);
create index incidente_estado_servicio_idx on incidente (estado, servicio_id);
create index incidente_municipio_idx on incidente (municipio_codigo);
create index incidente_centroide_gix on incidente using gist (centroide);

-- Reporte: novedad individual de un ciudadano
create table reporte (
  id                 uuid primary key default gen_random_uuid(),
  client_request_id  uuid not null unique,            -- idempotencia (req. 22)
  ciudadano_id       uuid references ciudadano(id) on delete set null,
  servicio_id        smallint not null references servicio(id),
  municipio_codigo   char(5) references municipio(codigo_dane),
  ubicacion          geography(Point, 4326) not null, -- latitud/longitud del ER
  descripcion        text check (char_length(descripcion) <= 1000),
  url_evidencia      text,
  inicio_estimado    timestamptz,
  estado             estado_reporte not null default 'recibido',
  incidente_id       uuid references incidente(id) on delete set null,
  creado_en          timestamptz not null default now()
);
create index reporte_ubicacion_gix on reporte using gist (ubicacion);
create index reporte_zona_idx on reporte (municipio_codigo, servicio_id, creado_en desc);
create index reporte_incidente_idx on reporte (incidente_id);
create index reporte_ciudadano_idx on reporte (ciudadano_id);

-- Confirmaciones ciudadanas (restablecimiento / sigue sin servicio)
create table confirmacion_ciudadana (
  id            uuid primary key default gen_random_uuid(),
  incidente_id  uuid not null references incidente(id) on delete cascade,
  ciudadano_id  uuid not null references ciudadano(id) on delete cascade,
  tipo          tipo_confirmacion not null,
  ubicacion     geography(Point, 4326),
  creado_en     timestamptz not null default now(),
  unique (incidente_id, ciudadano_id, tipo)
);
create index confirmacion_incidente_idx on confirmacion_ciudadana (incidente_id);

-- Denuncia anónima: NO tiene columnas que identifiquen al denunciante
create table denuncia (
  id                 uuid primary key default gen_random_uuid(),
  client_request_id  uuid not null unique,
  servicio_id        smallint not null references servicio(id),
  municipio_codigo   char(5) references municipio(codigo_dane),
  ubicacion_aprox    geography(Point, 4326),          -- opcional y aproximada
  descripcion        text not null check (char_length(descripcion) between 10 and 2000),
  url_evidencia      text,
  estado             estado_denuncia not null default 'recibida',
  seguimiento_hash   text not null unique,            -- hash del código que solo conoce el denunciante
  creada_en          timestamptz not null default now()
);
create index denuncia_estado_idx on denuncia (estado, municipio_codigo);

-- Validación / moderación hecha por operadores (sobre un reporte o una denuncia)
create table validacion (
  id           uuid primary key default gen_random_uuid(),
  reporte_id   uuid references reporte(id) on delete cascade,
  denuncia_id  uuid references denuncia(id) on delete cascade,
  operador_id  uuid not null references operador(id),
  estado       estado_validacion not null default 'pendiente',
  comentario   text,
  fecha        timestamptz not null default now(),
  check (num_nonnulls(reporte_id, denuncia_id) = 1)
);

-- Respuesta del operador (trazabilidad de la atención)
create table respuesta (
  id            uuid primary key default gen_random_uuid(),
  incidente_id  uuid references incidente(id) on delete cascade,
  reporte_id    uuid references reporte(id) on delete cascade,
  operador_id   uuid not null references operador(id),
  mensaje       text not null,
  fecha_resp    timestamptz not null default now(),
  check (num_nonnulls(incidente_id, reporte_id) >= 1)
);

-- Indicadores consolidados (alimentan los datos abiertos, ADR-04)
create table indicador (
  id                uuid primary key default gen_random_uuid(),
  tipo              text not null,
  valor             numeric not null,
  servicio_id       smallint references servicio(id),
  municipio_codigo  char(5) references municipio(codigo_dane),
  periodo_inicio    date not null,
  periodo_fin       date not null,
  fecha_calculo     timestamptz not null default now(),
  check (periodo_fin >= periodo_inicio)
);
create index indicador_consulta_idx on indicador (tipo, servicio_id, municipio_codigo, periodo_inicio);
