/**
 * SERVI-RED — Supabase Client & API Layer
 * ADR-01: Backend as a Service via Supabase (PostgreSQL + PostGIS)
 *
 * Reemplaza SUPABASE_URL y SUPABASE_ANON_KEY con las credenciales reales
 * una vez el equipo de backend configure el proyecto en Supabase.
 */

// ─────────────────────────────────────────────────────────────
// CONFIGURACIÓN (reemplazar con credenciales reales)
// ─────────────────────────────────────────────────────────────
const SUPABASE_URL = 'https://YOUR_PROJECT_ID.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR_ANON_KEY';

// ─────────────────────────────────────────────────────────────
// DETECCIÓN DE MODO: real vs mock
// ─────────────────────────────────────────────────────────────
const IS_MOCK_MODE = SUPABASE_URL.includes('YOUR_PROJECT_ID');

// ─────────────────────────────────────────────────────────────
// COLA LOCAL OFFLINE (ADR — Restricción 4)
// Persiste reportes en localStorage para reintentos automáticos
// ─────────────────────────────────────────────────────────────
const OfflineQueue = {
  KEY: 'servi_red_offline_queue',

  enqueue(item) {
    const queue = this.getAll();
    queue.push({ ...item, queued_at: new Date().toISOString(), retries: 0 });
    localStorage.setItem(this.KEY, JSON.stringify(queue));
    console.log('[OfflineQueue] Item encolado:', item);
  },

  getAll() {
    try {
      return JSON.parse(localStorage.getItem(this.KEY) || '[]');
    } catch {
      return [];
    }
  },

  remove(client_request_id) {
    const queue = this.getAll().filter(i => i.client_request_id !== client_request_id);
    localStorage.setItem(this.KEY, JSON.stringify(queue));
  },

  async processAll() {
    const queue = this.getAll();
    if (queue.length === 0) return;
    console.log(`[OfflineQueue] Procesando ${queue.length} item(s) pendientes...`);
    for (const item of queue) {
      try {
        await SupabaseAPI.insertReporte(item, true); // skipQueue = true
        this.remove(item.client_request_id);
        console.log('[OfflineQueue] Item enviado:', item.client_request_id);
      } catch (err) {
        item.retries = (item.retries || 0) + 1;
        console.warn('[OfflineQueue] Reintento fallido:', err);
        if (item.retries >= 5) {
          console.error('[OfflineQueue] Máximo reintentos alcanzado para:', item.client_request_id);
        }
      }
    }
  }
};

// Escucha reconexión de red y procesa la cola automáticamente
window.addEventListener('online', () => {
  console.log('[Network] Conexión restaurada. Procesando cola offline...');
  OfflineQueue.processAll();
  document.dispatchEvent(new CustomEvent('servi-red:online'));
});
window.addEventListener('offline', () => {
  document.dispatchEvent(new CustomEvent('servi-red:offline'));
});

// ─────────────────────────────────────────────────────────────
// DATOS MOCK (para desarrollo sin backend)
// ─────────────────────────────────────────────────────────────
const MockDB = {
  reportes: [
    {
      id: 'RPT-2024-001',
      client_request_id: 'crid-001',
      tipo_servicio: 'energia',
      descripcion: 'Apagón total en el barrio desde las 7am',
      latitud: 4.7110,
      longitud: -74.0721,
      municipio: 'Bogotá D.C.',
      estado: 'en_atencion',
      created_at: new Date(Date.now() - 3600000).toISOString(),
      hora_inicio: '07:00',
      magnitud_area: 'barrio',
      foto_url: null,
      confirmaciones: 12,
      timeline: [
        { estado: 'recibido', ts: new Date(Date.now() - 3600000).toISOString(), nota: 'Reporte registrado exitosamente' },
        { estado: 'en_atencion', ts: new Date(Date.now() - 1800000).toISOString(), nota: 'Operador asignado — Codensa' },
      ]
    },
    {
      id: 'RPT-2024-002',
      client_request_id: 'crid-002',
      tipo_servicio: 'agua',
      descripcion: 'Sin servicio de agua potable, corte sin previo aviso',
      latitud: 4.7200,
      longitud: -74.0650,
      municipio: 'Bogotá D.C.',
      estado: 'resuelto',
      created_at: new Date(Date.now() - 7200000).toISOString(),
      hora_inicio: '06:00',
      magnitud_area: 'manzana',
      foto_url: null,
      confirmaciones: 7,
      timeline: [
        { estado: 'recibido', ts: new Date(Date.now() - 7200000).toISOString(), nota: 'Reporte registrado exitosamente' },
        { estado: 'en_atencion', ts: new Date(Date.now() - 5400000).toISOString(), nota: 'Técnico en camino — Acueducto Bogotá' },
        { estado: 'resuelto', ts: new Date(Date.now() - 1200000).toISOString(), nota: 'Servicio restablecido. Duración: 1h 45min' }
      ]
    },
    {
      id: 'RPT-2024-003',
      client_request_id: 'crid-003',
      tipo_servicio: 'gas',
      descripcion: 'Olor fuerte a gas, posible fuga en la cuadra',
      latitud: 4.7050,
      longitud: -74.0800,
      municipio: 'Bogotá D.C.',
      estado: 'recibido',
      created_at: new Date(Date.now() - 900000).toISOString(),
      hora_inicio: '15:00',
      magnitud_area: 'cuadra',
      foto_url: null,
      confirmaciones: 3,
      timeline: [
        { estado: 'recibido', ts: new Date(Date.now() - 900000).toISOString(), nota: 'Reporte registrado exitosamente' }
      ]
    }
  ],

  denuncias: [],
  gamificacion: {
    insignias: [
      { id: 'first_report', nombre: 'Primer Reporte', descripcion: 'Enviaste tu primer reporte ciudadano', icono: '🏅', nivel: 1 },
      { id: 'community_guard', nombre: 'Guardián Comunitario', descripcion: '5 reportes verificados por la comunidad', icono: '🛡️', nivel: 2 },
      { id: 'fast_reporter', nombre: 'Alerta Temprana', descripcion: 'Reportaste en menos de 5 min del corte', icono: '⚡', nivel: 1 },
      { id: 'validator', nombre: 'Validador Activo', descripcion: 'Confirmaste 10 reportes de vecinos', icono: '✅', nivel: 2 },
    ],
    usuario: { reportes_enviados: 0, confirmaciones_dadas: 0, insignias_obtenidas: [] }
  }
};

// ─────────────────────────────────────────────────────────────
// API PRINCIPAL — SERVI-RED
// Métodos que se comunican con Supabase (real o mock)
// ─────────────────────────────────────────────────────────────
const SupabaseAPI = {

  // Headers base para peticiones REST a Supabase
  _headers() {
    return {
      'Content-Type': 'application/json',
      'apikey': SUPABASE_ANON_KEY,
      'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
      'Prefer': 'return=representation'
    };
  },

  // ── RF-01: Insertar reporte de corte/interrupción ─────────
  async insertReporte(payload, skipQueue = false) {
    const client_request_id = payload.client_request_id || crypto.randomUUID();

    if (IS_MOCK_MODE) {
      // Simular latencia de red
      await _delay(800);
      const nuevo = {
        ...payload,
        id: `RPT-${Date.now()}`,
        client_request_id,
        estado: 'recibido',
        created_at: new Date().toISOString(),
        confirmaciones: 0,
        timeline: [{ estado: 'recibido', ts: new Date().toISOString(), nota: 'Reporte registrado exitosamente' }]
      };
      MockDB.reportes.unshift(nuevo);
      _actualizarGamificacion('reporte');
      return { data: nuevo, error: null };
    }

    if (!navigator.onLine && !skipQueue) {
      OfflineQueue.enqueue({ ...payload, client_request_id });
      return {
        data: { id: client_request_id, estado: 'en_cola_offline', client_request_id },
        error: null,
        offline: true
      };
    }

    try {
      const res = await fetch(`${SUPABASE_URL}/rest/v1/reportes`, {
        method: 'POST',
        headers: this._headers(),
        body: JSON.stringify({ ...payload, client_request_id })
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.message || 'Error al insertar reporte');
      return { data: data[0], error: null };
    } catch (err) {
      if (!skipQueue) OfflineQueue.enqueue({ ...payload, client_request_id });
      return { data: null, error: err.message };
    }
  },

  // ── RF-02: Notificar restablecimiento de servicio ─────────
  async notificarRestablecimiento(reporte_id, coordenadas) {
    if (IS_MOCK_MODE) {
      await _delay(600);
      const reporte = MockDB.reportes.find(r => r.id === reporte_id);
      if (reporte) {
        reporte.estado = 'resuelto';
        reporte.timeline.push({ estado: 'resuelto', ts: new Date().toISOString(), nota: 'Servicio restablecido reportado por ciudadano' });
      }
      return { data: { ok: true }, error: null };
    }

    try {
      const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/notificar_restablecimiento`, {
        method: 'POST',
        headers: this._headers(),
        body: JSON.stringify({ p_reporte_id: reporte_id, p_lat: coordenadas.lat, p_lng: coordenadas.lng })
      });
      return { data: await res.json(), error: null };
    } catch (err) {
      return { data: null, error: err.message };
    }
  },

  // ── RF-03: Confirmar reporte (validación comunitaria) ─────
  async confirmarReporte(reporte_id) {
    if (IS_MOCK_MODE) {
      await _delay(400);
      const reporte = MockDB.reportes.find(r => r.id === reporte_id);
      if (reporte) reporte.confirmaciones = (reporte.confirmaciones || 0) + 1;
      _actualizarGamificacion('confirmacion');
      return { data: { confirmaciones: reporte?.confirmaciones }, error: null };
    }

    try {
      const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/confirmar_reporte`, {
        method: 'POST',
        headers: this._headers(),
        body: JSON.stringify({ p_reporte_id: reporte_id })
      });
      return { data: await res.json(), error: null };
    } catch (err) {
      return { data: null, error: err.message };
    }
  },

  // ── RF-04: Enviar denuncia anónima de fraude ──────────────
  async insertDenuncia(payload) {
    const client_request_id = crypto.randomUUID();
    if (IS_MOCK_MODE) {
      await _delay(700);
      const nueva = { ...payload, id: `DEN-${Date.now()}`, client_request_id, estado: 'en_moderacion', created_at: new Date().toISOString() };
      MockDB.denuncias.push(nueva);
      return { data: nueva, error: null };
    }

    try {
      // Nota: No se envía ningún dato personal — ADR-02 Privacidad por Diseño
      const res = await fetch(`${SUPABASE_URL}/rest/v1/denuncias_anonimas`, {
        method: 'POST',
        headers: this._headers(),
        body: JSON.stringify({ ...payload, client_request_id })
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.message || 'Error al enviar denuncia');
      return { data: data[0], error: null };
    } catch (err) {
      return { data: null, error: err.message };
    }
  },

  // ── RF-05: Consultar estado de reporte por ID ─────────────
  async getReportePorId(reporte_id) {
    if (IS_MOCK_MODE) {
      await _delay(500);
      const reporte = MockDB.reportes.find(r => r.id === reporte_id);
      if (!reporte) return { data: null, error: 'Reporte no encontrado' };
      return { data: reporte, error: null };
    }

    try {
      const res = await fetch(
        `${SUPABASE_URL}/rest/v1/reportes?id=eq.${encodeURIComponent(reporte_id)}&select=*,timeline_eventos(*)`,
        { headers: this._headers() }
      );
      const data = await res.json();
      if (!data?.length) return { data: null, error: 'Reporte no encontrado' };
      return { data: data[0], error: null };
    } catch (err) {
      return { data: null, error: err.message };
    }
  },

  // ── Obtener reportes cercanos (PostGIS ST_DWithin) ────────
  async getReportesCercanos(lat, lng, radiusMeters = 2000) {
    if (IS_MOCK_MODE) {
      await _delay(400);
      // Filtro simulado por distancia aproximada
      const cercanos = MockDB.reportes.filter(r => {
        const dist = _haversine(lat, lng, r.latitud, r.longitud);
        return dist <= radiusMeters && r.estado !== 'resuelto';
      });
      return { data: cercanos, error: null };
    }

    try {
      const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/get_reportes_cercanos`, {
        method: 'POST',
        headers: this._headers(),
        body: JSON.stringify({ p_lat: lat, p_lng: lng, p_radio_metros: radiusMeters })
      });
      return { data: await res.json(), error: null };
    } catch (err) {
      return { data: null, error: err.message };
    }
  },

  // ── Suscripción Realtime a cambios de estado ──────────────
  subscribeToReporte(reporte_id, callback) {
    if (IS_MOCK_MODE) {
      // Simular WebSocket con polling mock
      console.log('[Realtime] Modo mock — simulando suscripción para:', reporte_id);
      return { unsubscribe: () => {} };
    }
    // Supabase Realtime — ADR: WebSockets
    console.log('[Realtime] Suscribiendo a cambios de reporte:', reporte_id);
    // Implementar con @supabase/supabase-js cuando esté disponible
    return { unsubscribe: () => {} };
  },

  // ── Gamificación: Obtener perfil del usuario ──────────────
  getGamificacionPerfil() {
    const stored = localStorage.getItem('servi_red_user_stats');
    if (stored) return JSON.parse(stored);
    return MockDB.gamificacion.usuario;
  }
};

// ─────────────────────────────────────────────────────────────
// UTILIDADES INTERNAS
// ─────────────────────────────────────────────────────────────
function _delay(ms) { return new Promise(r => setTimeout(r, ms)); }

function _haversine(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(dLat/2)**2 + Math.cos(lat1*Math.PI/180)*Math.cos(lat2*Math.PI/180)*Math.sin(dLng/2)**2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
}

function _actualizarGamificacion(tipo) {
  const stats = SupabaseAPI.getGamificacionPerfil();
  if (tipo === 'reporte') stats.reportes_enviados = (stats.reportes_enviados || 0) + 1;
  if (tipo === 'confirmacion') stats.confirmaciones_dadas = (stats.confirmaciones_dadas || 0) + 1;

  // Evaluar insignias
  const insignias = stats.insignias_obtenidas || [];
  if (stats.reportes_enviados >= 1 && !insignias.includes('first_report')) insignias.push('first_report');
  if (stats.reportes_enviados >= 5 && !insignias.includes('community_guard')) insignias.push('community_guard');
  if (stats.confirmaciones_dadas >= 10 && !insignias.includes('validator')) insignias.push('validator');

  stats.insignias_obtenidas = insignias;
  localStorage.setItem('servi_red_user_stats', JSON.stringify(stats));
}

// Exportar para uso en otros módulos
window.SupabaseAPI = SupabaseAPI;
window.OfflineQueue = OfflineQueue;
window.MockDB = MockDB;
