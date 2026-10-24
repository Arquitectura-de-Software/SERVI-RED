-- =====================================================================
-- SERVI-RED | Persona 1 | Migración 6: RLS base (denegar por defecto)
-- =====================================================================
-- En Supabase, toda tabla de "public" queda expuesta por la API REST. Se
-- activa RLS en TODAS y, sin políticas, nadie (anon/authenticated) accede.
-- Las políticas reales por rol llegan en la Fase 2.

alter table departamento           enable row level security;
alter table municipio              enable row level security;
alter table codigo_postal          enable row level security;
alter table empresa                enable row level security;
alter table servicio               enable row level security;
alter table empresa_cobertura      enable row level security;
alter table perfil                 enable row level security;
alter table ciudadano              enable row level security;
alter table operador               enable row level security;
alter table incidente              enable row level security;
alter table reporte                enable row level security;
alter table confirmacion_ciudadana enable row level security;
alter table denuncia               enable row level security;
alter table validacion             enable row level security;
alter table respuesta              enable row level security;
alter table indicador              enable row level security;
alter table audit_log              enable row level security;
alter table evento_outbox          enable row level security;
alter table transicion_incidente   enable row level security;

-- Los catálogos son información pública: lectura abierta
create policy "catalogo_lectura_publica" on departamento      for select to anon, authenticated using (true);
create policy "catalogo_lectura_publica" on municipio         for select to anon, authenticated using (true);
create policy "catalogo_lectura_publica" on codigo_postal     for select to anon, authenticated using (true);
create policy "catalogo_lectura_publica" on servicio          for select to anon, authenticated using (true);
create policy "catalogo_lectura_publica" on empresa           for select to anon, authenticated using (true);
create policy "catalogo_lectura_publica" on empresa_cobertura for select to anon, authenticated using (true);
