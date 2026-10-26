-- ═══════════════════════════════════════════════════════════════════
-- SERVI-RED — Esquema SQL para Supabase (PostgreSQL + PostGIS)
-- ADR-01: Backend as a Service con extensiones espaciales
-- ═══════════════════════════════════════════════════════════════════

-- Habilitar PostGIS para consultas espaciales (ST_DWithin, etc.)
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─────────────────────────────────────────────────────────────
-- TABLA: reportes
-- Almacena los reportes de interrupciones ciudadanas (RF-01)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS reportes (
  id                  TEXT PRIMARY KEY DEFAULT 'RPT-' || to_char(NOW(), 'YYYY-') || LPAD(nextval('reporte_seq')::text, 6, '0'),
  client_request_id   UUID UNIQUE NOT NULL DEFAULT uuid_generate_v4(), -- Idempotencia (RNF-22)
  tipo_servicio       TEXT NOT NULL CHECK (tipo_servicio IN ('energia','agua','gas','alcantarillado','aseo')),
  descripcion         TEXT NOT NULL CHECK (length(descripcion) >= 10),
  municipio           TEXT,
  hora_inicio         TIME,
  magnitud_area       TEXT CHECK (magnitud_area IN ('edificio','manzana','cuadra','barrio','sector')),
  foto_url            TEXT,                             -- URL de Supabase Storage
  latitud             DOUBLE PRECISION NOT NULL,
  longitud            DOUBLE PRECISION NOT NULL,
  geom                GEOGRAPHY(POINT, 4326),           -- Columna espacial PostGIS
  estado              TEXT NOT NULL DEFAULT 'recibido'
                        CHECK (estado IN ('recibido','en_atencion','resuelto')),
  confirmaciones      INTEGER NOT NULL DEFAULT 0,
  duracion_minutos    INTEGER,                          -- Calculado automáticamente al resolver
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at         TIMESTAMPTZ
);

-- Secuencia para IDs legibles
CREATE SEQUENCE IF NOT EXISTS reporte_seq START 1;

-- Índice espacial para ST_DWithin (PostGIS)
CREATE INDEX IF NOT EXISTS idx_reportes_geom ON reportes USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_reportes_estado ON reportes (estado);
CREATE INDEX IF NOT EXISTS idx_reportes_tipo ON reportes (tipo_servicio);

-- Trigger: actualizar columna geom automáticamente al insertar/actualizar
CREATE OR REPLACE FUNCTION sync_reporte_geom()
RETURNS TRIGGER AS $$
BEGIN
  NEW.geom = ST_SetSRID(ST_MakePoint(NEW.longitud, NEW.latitud), 4326)::geography;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_reporte_geom
  BEFORE INSERT OR UPDATE ON reportes
  FOR EACH ROW EXECUTE FUNCTION sync_reporte_geom();


-- ─────────────────────────────────────────────────────────────
-- TABLA: timeline_eventos
-- Historial de cambios de estado por reporte (RF-05)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS timeline_eventos (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  reporte_id  TEXT NOT NULL REFERENCES reportes(id) ON DELETE CASCADE,
  estado      TEXT NOT NULL CHECK (estado IN ('recibido','en_atencion','resuelto')),
  nota        TEXT,
  operador    TEXT,                                     -- ID del operador que cambió el estado
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_timeline_reporte ON timeline_eventos (reporte_id);


-- ─────────────────────────────────────────────────────────────
-- TABLA: denuncias_anonimas
-- Canal seguro para fraudes (RF-04) — Sin PII
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS denuncias_anonimas (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  client_request_id   UUID UNIQUE NOT NULL DEFAULT uuid_generate_v4(),
  tipo_fraude         TEXT NOT NULL CHECK (tipo_fraude IN (
                        'conexion_clandestina','medidor_alterado',
                        'derivacion_no_autorizada','robo_servicio','otro')),
  servicio            TEXT NOT NULL CHECK (servicio IN ('energia','agua','gas')),
  descripcion         TEXT NOT NULL CHECK (length(descripcion) >= 15),
  municipio           TEXT,
  -- Coordenadas REDONDEADAS (±1km) — Privacidad por Diseño
  latitud             NUMERIC(5,2),
  longitud            NUMERIC(5,2),
  geom                GEOGRAPHY(POINT, 4326),
  estado              TEXT NOT NULL DEFAULT 'en_moderacion'
                        CHECK (estado IN ('en_moderacion','aprobada','rechazada','transmitida')),
  operador_destino    TEXT,                             -- Se asigna post-moderación
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
  -- SIN user_id, SIN email, SIN nombre — Garantía de anonimato total
);

CREATE INDEX IF NOT EXISTS idx_denuncias_estado ON denuncias_anonimas (estado);


-- ─────────────────────────────────────────────────────────────
-- TABLA: outbox_eventos
-- Patrón Outbox para notificaciones asíncronas (ADR-03 / RF-06)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS outbox_eventos (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  reporte_id      TEXT REFERENCES reportes(id) ON DELETE SET NULL,
  tipo_evento     TEXT NOT NULL CHECK (tipo_evento IN (
                    'reporte_creado','estado_cambiado','restablecimiento_confirmado',
                    'denuncia_recibida','push_notification')),
  payload         JSONB NOT NULL DEFAULT '{}',
  canal           TEXT CHECK (canal IN ('push_fcm','in_app','email','sms')),
  intentos        INTEGER NOT NULL DEFAULT 0,
  max_intentos    INTEGER NOT NULL DEFAULT 5,           -- Resiliencia: máx reintentos
  estado          TEXT NOT NULL DEFAULT 'pendiente'
                    CHECK (estado IN ('pendiente','procesando','enviado','fallido')),
  error_detalle   TEXT,                                 -- Log de fallos (sin invalidar reporte)
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_outbox_estado ON outbox_eventos (estado, created_at);


-- ─────────────────────────────────────────────────────────────
-- TABLA: push_tokens
-- Tokens FCM para notificaciones push (RF-06)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS push_tokens (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  token       TEXT UNIQUE NOT NULL,
  plataforma  TEXT CHECK (plataforma IN ('android','ios','web')),
  activo      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
  -- Sin user_id — tokens anónimos ligados a sesión de dispositivo
);


-- ─────────────────────────────────────────────────────────────
-- ROW LEVEL SECURITY (RLS) — ADR-02
-- Políticas de acceso sin autenticación obligatoria
-- ─────────────────────────────────────────────────────────────
ALTER TABLE reportes ENABLE ROW LEVEL SECURITY;
ALTER TABLE timeline_eventos ENABLE ROW LEVEL SECURITY;
ALTER TABLE denuncias_anonimas ENABLE ROW LEVEL SECURITY;
ALTER TABLE outbox_eventos ENABLE ROW LEVEL SECURITY;

-- Cualquier usuario (anon o auth) puede LEER reportes no resueltos
CREATE POLICY "public_read_reportes" ON reportes
  FOR SELECT TO anon, authenticated
  USING (true);

-- Cualquier usuario puede INSERTAR un reporte (sin login)
CREATE POLICY "public_insert_reportes" ON reportes
  FOR INSERT TO anon, authenticated
  WITH CHECK (true);

-- Solo el sistema (service_role) puede actualizar estados
CREATE POLICY "system_update_reportes" ON reportes
  FOR UPDATE TO service_role
  USING (true);

-- Timeline: lectura pública, escritura solo sistema
CREATE POLICY "public_read_timeline" ON timeline_eventos
  FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "system_write_timeline" ON timeline_eventos
  FOR INSERT TO service_role WITH CHECK (true);

-- Denuncias: inserción anónima, lectura prohibida (solo moderadores)
CREATE POLICY "anon_insert_denuncia" ON denuncias_anonimas
  FOR INSERT TO anon, authenticated
  WITH CHECK (true);
-- Sin SELECT policy para anon: nadie puede leer denuncias sin ser moderador


-- ─────────────────────────────────────────────────────────────
-- RPC: get_reportes_cercanos (PostGIS ST_DWithin)
-- Módulo B — Filtro de duplicados espaciales
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_reportes_cercanos(
  p_lat           DOUBLE PRECISION,
  p_lng           DOUBLE PRECISION,
  p_radio_metros  INTEGER DEFAULT 2000
)
RETURNS SETOF reportes AS $$
  SELECT r.*
  FROM reportes r
  WHERE r.estado != 'resuelto'
    AND ST_DWithin(
      r.geom,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
      p_radio_metros
    )
  ORDER BY r.created_at DESC
  LIMIT 50;
$$ LANGUAGE SQL STABLE SECURITY DEFINER;


-- ─────────────────────────────────────────────────────────────
-- RPC: confirmar_reporte (RF-03)
-- Validación comunitaria — incrementa contador
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION confirmar_reporte(p_reporte_id TEXT)
RETURNS TABLE(confirmaciones INTEGER) AS $$
DECLARE
  umbral_restablecimiento INTEGER := 5;
  v_confirmaciones INTEGER;
BEGIN
  UPDATE reportes
  SET confirmaciones = confirmaciones + 1
  WHERE id = p_reporte_id
  RETURNING confirmaciones INTO v_confirmaciones;

  -- Si supera el umbral, calcular duración y marcar resuelto automáticamente
  IF v_confirmaciones >= umbral_restablecimiento THEN
    UPDATE reportes
    SET estado = 'resuelto',
        resolved_at = NOW(),
        duracion_minutos = EXTRACT(EPOCH FROM (NOW() - created_at)) / 60
    WHERE id = p_reporte_id AND estado != 'resuelto';

    -- Emitir evento al outbox para notificaciones
    INSERT INTO outbox_eventos (reporte_id, tipo_evento, payload, canal)
    VALUES (p_reporte_id, 'restablecimiento_confirmado',
      jsonb_build_object('reporte_id', p_reporte_id, 'confirmaciones', v_confirmaciones),
      'in_app');
  END IF;

  RETURN QUERY SELECT v_confirmaciones;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ─────────────────────────────────────────────────────────────
-- RPC: notificar_restablecimiento (RF-02)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION notificar_restablecimiento(
  p_reporte_id  TEXT,
  p_lat         DOUBLE PRECISION,
  p_lng         DOUBLE PRECISION
)
RETURNS JSONB AS $$
DECLARE
  v_duracion INTEGER;
BEGIN
  UPDATE reportes
  SET estado = 'resuelto',
      resolved_at = NOW(),
      duracion_minutos = EXTRACT(EPOCH FROM (NOW() - created_at)) / 60
  WHERE id = p_reporte_id AND estado != 'resuelto'
  RETURNING duracion_minutos INTO v_duracion;

  -- Evento al outbox (ADR-03)
  INSERT INTO outbox_eventos (reporte_id, tipo_evento, payload, canal)
  VALUES (p_reporte_id, 'estado_cambiado',
    jsonb_build_object('estado', 'resuelto', 'duracion_minutos', v_duracion),
    'push_fcm');

  RETURN jsonb_build_object('ok', true, 'duracion_minutos', v_duracion);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ─────────────────────────────────────────────────────────────
-- TRIGGER: Insertar en outbox al crear reporte (ADR-03)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION on_reporte_created()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO outbox_eventos (reporte_id, tipo_evento, payload, canal)
  VALUES (
    NEW.id,
    'reporte_creado',
    jsonb_build_object(
      'reporte_id', NEW.id,
      'tipo_servicio', NEW.tipo_servicio,
      'municipio', NEW.municipio,
      'estado', NEW.estado
    ),
    'in_app'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_reporte_created
  AFTER INSERT ON reportes
  FOR EACH ROW EXECUTE FUNCTION on_reporte_created();


-- ─────────────────────────────────────────────────────────────
-- TRIGGER: Registrar cambios de estado en timeline
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION on_reporte_estado_changed()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.estado IS DISTINCT FROM NEW.estado THEN
    INSERT INTO timeline_eventos (reporte_id, estado, nota)
    VALUES (NEW.id, NEW.estado,
      CASE NEW.estado
        WHEN 'en_atencion' THEN 'Operador asignado al reporte'
        WHEN 'resuelto' THEN 'Servicio restablecido. Duración: ' || COALESCE(NEW.duracion_minutos::text, '?') || ' min'
        ELSE 'Estado actualizado'
      END
    );

    -- Emitir notificación push (ADR-03)
    INSERT INTO outbox_eventos (reporte_id, tipo_evento, payload, canal)
    VALUES (NEW.id, 'estado_cambiado',
      jsonb_build_object('reporte_id', NEW.id, 'estado_nuevo', NEW.estado, 'estado_anterior', OLD.estado),
      'push_fcm');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_reporte_estado_changed
  AFTER UPDATE ON reportes
  FOR EACH ROW EXECUTE FUNCTION on_reporte_estado_changed();
