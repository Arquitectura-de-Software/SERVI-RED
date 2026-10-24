-- =====================================================================
-- SERVI-RED | Persona 1 | Migración 1: extensiones y tipos enumerados
-- =====================================================================

-- PostGIS (consultas geoespaciales, ADR-01). En Supabase las extensiones
-- viven en el esquema "extensions", que ya está en el search_path.
create extension if not exists postgis with schema extensions;

-- Servicios públicos domiciliarios contemplados (restricción 1 del SAD)
create type tipo_servicio as enum ('energia', 'gas', 'acueducto', 'alcantarillado', 'aseo');

-- Roles funcionales de la plataforma (ADR-02)
create type rol_usuario as enum ('ciudadano', 'operador', 'regulador', 'admin');

-- Ciclo de vida de un reporte individual (supuesto 11: reporte != incidente)
create type estado_reporte as enum ('recibido', 'vinculado', 'descartado');

-- Ciclo de vida de un incidente (req. 20: solo transiciones permitidas)
create type estado_incidente as enum ('recibido', 'en_atencion', 'restablecido', 'cerrado');

-- Denuncias anónimas de conexiones fraudulentas
create type estado_denuncia as enum ('recibida', 'en_revision', 'validada', 'descartada');

-- Validación / moderación hecha por el operador
create type estado_validacion as enum ('pendiente', 'aprobada', 'rechazada');

-- Tipos de confirmación ciudadana sobre un incidente
create type tipo_confirmacion as enum ('restablecido', 'sin_servicio');

-- Estado de los eventos del outbox (ADR-03)
create type estado_evento as enum ('pendiente', 'procesado', 'fallido');
