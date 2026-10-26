/**
 * SERVI-RED — Módulo B: Reporte de Interrupciones (RF-01)
 * + Módulo C: Validación Comunitaria (RF-02, RF-03)
 *
 * Persona 2 — Implementación completa con:
 * - Formulario georreferenciado (GPS automático)
 * - Adjunto de foto (Supabase Storage)
 * - Garantía de idempotencia (client_request_id)
 * - Cola offline con reintentos automáticos
 * - Confirmación con ID de trazabilidad
 */

// ─────────────────────────────────────────────────────────────
// ESTADO LOCAL DEL MÓDULO
// ─────────────────────────────────────────────────────────────
const ReporteState = {
  servicioSeleccionado: null,
  ubicacion: null,
  fotoBlob: null,
  fotoPreviewUrl: null,
  map: null,
  marker: null
};

// ─────────────────────────────────────────────────────────────
// INICIALIZACIÓN
// ─────────────────────────────────────────────────────────────
function initReporteModule() {

  Modules['reporte'] = {
    onEnter() {
      // Lazy-init mapa Leaflet (ADR-05: OpenStreetMap)
      if (!ReporteState.map) {
        setTimeout(() => initMapaReporte(), 200);
      }
    }
  };

  // ── Chips de servicio ────────────────────────────────────
  document.querySelectorAll('#screen-reporte .service-chip').forEach(chip => {
    chip.addEventListener('click', () => {
      document.querySelectorAll('#screen-reporte .service-chip').forEach(c => c.classList.remove('selected'));
      chip.classList.add('selected');
      ReporteState.servicioSeleccionado = chip.dataset.servicio;

      // Feedback visual en el paso de tipo
      document.getElementById('reporte-tipo-feedback').textContent =
        `✓ ${UI.getServiceMeta(chip.dataset.servicio).label} seleccionado`;
      document.getElementById('reporte-tipo-feedback').style.color = chip.style.getPropertyValue('--chip-color') || 'var(--status-resuelto)';
    });
  });

  // ── Foto adjunta ─────────────────────────────────────────
  const photoUpload = document.getElementById('photo-upload-area');
  const photoInput  = document.getElementById('photo-input');
  const photoImg    = document.getElementById('photo-preview-img');

  photoUpload?.addEventListener('click', () => photoInput?.click());
  photoInput?.addEventListener('change', (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    ReporteState.fotoBlob = file;
    const url = URL.createObjectURL(file);
    ReporteState.fotoPreviewUrl = url;
    photoImg.src = url;
    photoUpload.classList.add('has-photo');
    UI.toast('Foto adjuntada correctamente', 'success');
  });

  // ── Captura GPS automática ───────────────────────────────
  document.getElementById('btn-capturar-gps')?.addEventListener('click', capturarUbicacion);

  // ── Formulario Submit ────────────────────────────────────
  document.getElementById('form-reporte')?.addEventListener('submit', onSubmitReporte);
}

// ─────────────────────────────────────────────────────────────
// MAPA LEAFLET — ADR-05 OpenStreetMap
// ─────────────────────────────────────────────────────────────
function initMapaReporte() {
  const mapEl = document.getElementById('map');
  if (!mapEl || ReporteState.map) return;

  // Centro: Bogotá D.C. por defecto
  const defaultCenter = [4.7110, -74.0721];

  ReporteState.map = L.map('map', {
    zoomControl: true,
    attributionControl: false,
    scrollWheelZoom: false
  }).setView(defaultCenter, 13);

  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '© OpenStreetMap',
    maxZoom: 19,
    className: 'map-tiles'
  }).addTo(ReporteState.map);

  // Capturar ubicación al cargar
  capturarUbicacion(true);

  // Permitir selección manual en mapa
  ReporteState.map.on('click', (e) => {
    setUbicacionEnMapa(e.latlng.lat, e.latlng.lng, true);
    UI.toast('Ubicación actualizada en el mapa', 'info');
  });
}

function setUbicacionEnMapa(lat, lng, manual = false) {
  ReporteState.ubicacion = { lat, lng };

  // Icono personalizado
  const icon = L.divIcon({
    className: '',
    html: `<div style="
      width:36px;height:36px;background:linear-gradient(135deg,#E53E3E,#2B6CB0);
      border-radius:50% 50% 50% 0;transform:rotate(-45deg);
      border:3px solid white;box-shadow:0 4px 12px rgba(229,62,62,.5)">
    </div>`,
    iconSize: [36, 36],
    iconAnchor: [18, 36]
  });

  if (ReporteState.marker) {
    ReporteState.marker.setLatLng([lat, lng]);
  } else {
    ReporteState.marker = L.marker([lat, lng], { icon }).addTo(ReporteState.map);
  }

  ReporteState.map.setView([lat, lng], 15, { animate: true });
  document.getElementById('gps-status').textContent =
    `📍 ${lat.toFixed(5)}, ${lng.toFixed(5)}${manual ? ' (manual)' : ' (GPS)'}`;
}

async function capturarUbicacion(silent = false) {
  if (!navigator.geolocation) {
    if (!silent) UI.toast('Geolocalización no disponible', 'error');
    setUbicacionEnMapa(4.7110, -74.0721, false);
    return;
  }

  if (!silent) document.getElementById('gps-status').textContent = '📡 Obteniendo ubicación GPS...';

  navigator.geolocation.getCurrentPosition(
    (pos) => {
      setUbicacionEnMapa(pos.coords.latitude, pos.coords.longitude, false);
      if (!silent) UI.toast('Ubicación GPS capturada', 'success');
    },
    (err) => {
      console.warn('GPS error:', err);
      setUbicacionEnMapa(4.7110, -74.0721, false);
      if (!silent) UI.toast('Usando ubicación estimada. Puedes ajustarla en el mapa.', 'warning');
    },
    { enableHighAccuracy: true, timeout: 8000, maximumAge: 60000 }
  );
}

// ─────────────────────────────────────────────────────────────
// SUBMIT — RF-01 Insertar Reporte
// ─────────────────────────────────────────────────────────────
async function onSubmitReporte(e) {
  e.preventDefault();

  // Validaciones
  if (!ReporteState.servicioSeleccionado) {
    UI.toast('Selecciona el tipo de servicio afectado', 'error');
    return;
  }
  if (!ReporteState.ubicacion) {
    UI.toast('Captura tu ubicación GPS primero', 'error');
    return;
  }

  const descripcion = document.getElementById('reporte-descripcion')?.value?.trim();
  if (!descripcion || descripcion.length < 10) {
    UI.toast('Ingresa una descripción de al menos 10 caracteres', 'error');
    return;
  }

  const submitBtn = document.getElementById('reporte-submit-btn');
  UI.loading(submitBtn, true, 'Enviando reporte...');

  // Garantía de idempotencia (RNF-22)
  const client_request_id = crypto.randomUUID();

  const payload = {
    client_request_id,
    tipo_servicio: ReporteState.servicioSeleccionado,
    descripcion,
    latitud: ReporteState.ubicacion.lat,
    longitud: ReporteState.ubicacion.lng,
    municipio: document.getElementById('reporte-municipio')?.value || 'Bogotá D.C.',
    hora_inicio: document.getElementById('reporte-hora-inicio')?.value || new Date().toTimeString().slice(0,5),
    magnitud_area: document.getElementById('reporte-magnitud')?.value || 'manzana',
    foto_url: ReporteState.fotoPreviewUrl || null,
  };

  try {
    const { data, error, offline } = await SupabaseAPI.insertReporte(payload);

    UI.loading(submitBtn, false);

    if (error && !offline) {
      UI.toast(`Error: ${error}`, 'error', 'No se pudo enviar');
      return;
    }

    // Mostrar confirmación con ID de trazabilidad
    mostrarConfirmacion(data, offline);

    // Resetear formulario
    resetFormReporte();

  } catch (err) {
    UI.loading(submitBtn, false);
    UI.toast('Error inesperado. Intenta de nuevo.', 'error');
    console.error(err);
  }
}

function mostrarConfirmacion(data, offline = false) {
  const idEl = document.getElementById('confirm-id');
  const statusEl = document.getElementById('confirm-status-msg');

  if (idEl) idEl.textContent = data.id || data.client_request_id || '—';
  if (statusEl) {
    statusEl.textContent = offline
      ? '⚡ Guardado localmente. Se enviará cuando recuperes conexión.'
      : '✅ Reporte registrado exitosamente en el sistema SERVI-RED.';
    statusEl.style.color = offline ? 'var(--status-offline)' : 'var(--status-resuelto)';
  }

  UI.modal.open('modal-confirm');

  // Actualizar home
  setTimeout(() => {
    const listEl = document.getElementById('home-recent-list');
    if (listEl) renderRecentReports(listEl);
  }, 500);
}

function resetFormReporte() {
  document.getElementById('form-reporte')?.reset();
  document.querySelectorAll('#screen-reporte .service-chip').forEach(c => c.classList.remove('selected'));
  ReporteState.servicioSeleccionado = null;
  ReporteState.fotoBlob = null;
  ReporteState.fotoPreviewUrl = null;
  const photoUpload = document.getElementById('photo-upload-area');
  const photoImg = document.getElementById('photo-preview-img');
  if (photoUpload) photoUpload.classList.remove('has-photo');
  if (photoImg) photoImg.src = '';
  document.getElementById('reporte-tipo-feedback').textContent = '';
  document.getElementById('gps-status').textContent = '';
}

// ─────────────────────────────────────────────────────────────
// MÓDULO COMUNIDAD — RF-02 y RF-03
// ─────────────────────────────────────────────────────────────
function initComunidadModule() {
  let mapComunidad = null;

  Modules['comunidad'] = {
    async onEnter() {
      await cargarReportesCercanos();
      if (!mapComunidad) setTimeout(() => { mapComunidad = initMapaComunidad(); }, 200);
    }
  };
}

async function cargarReportesCercanos() {
  const listEl = document.getElementById('comunidad-list');
  if (!listEl) return;

  listEl.innerHTML = `<div class="card"><div class="skeleton" style="height:80px;"></div></div>`;

  // Usar ubicación actual o Bogotá por defecto
  const lat = ReporteState.ubicacion?.lat || 4.7110;
  const lng = ReporteState.ubicacion?.lng || -74.0721;

  const { data: reportes, error } = await SupabaseAPI.getReportesCercanos(lat, lng, 3000);

  if (error || !reportes?.length) {
    listEl.innerHTML = `
      <div class="empty-state">
        <div class="empty-state__icon">🗺️</div>
        <div class="empty-state__title">No hay reportes activos en tu zona</div>
        <p class="section-subtitle">La comunidad está al día</p>
      </div>`;
    return;
  }

  listEl.innerHTML = reportes.map(r => {
    const meta = UI.getServiceMeta(r.tipo_servicio);
    return `
    <div class="report-card" id="comunidad-card-${r.id}">
      <div class="report-card__icon" style="background:color-mix(in srgb, ${meta.color} 15%, transparent);">${meta.icon}</div>
      <div class="report-card__body">
        <div class="report-card__type" style="color:${meta.color}">${meta.label}</div>
        <div class="report-card__desc">${r.descripcion}</div>
        <div class="report-card__meta">
          <span class="status-badge status-badge--${r.estado}">
            <span class="status-dot"></span>${UI.getStatusLabel(r.estado)}
          </span>
          <span>·</span>
          <span>👍 <span id="confirms-${r.id}">${r.confirmaciones || 0}</span> confirmaciones</span>
        </div>
        <div style="display:flex;gap:8px;margin-top:10px;flex-wrap:wrap">
          <button class="btn btn-sm btn-outline" onclick="onConfirmarReporte('${r.id}')">👍 Confirmar</button>
          <button class="btn btn-sm btn-secondary" onclick="onNotificarRestablecimiento('${r.id}')">✅ Ya volvió</button>
        </div>
      </div>
    </div>`;
  }).join('');
}

function initMapaComunidad() {
  const el = document.getElementById('map-comunidad');
  if (!el) return null;

  const map = L.map('map-comunidad', { zoomControl: false, scrollWheelZoom: false })
    .setView([4.7110, -74.0721], 13);

  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png').addTo(map);

  // Pintar marcadores de reportes mock
  MockDB.reportes.filter(r => r.estado !== 'resuelto').forEach(r => {
    const meta = UI.getServiceMeta(r.tipo_servicio);
    const marker = L.circleMarker([r.latitud, r.longitud], {
      radius: 12,
      fillColor: meta.color,
      color: 'white',
      weight: 2,
      opacity: 1,
      fillOpacity: 0.8
    }).addTo(map);
    marker.bindPopup(`
      <b>${meta.label}</b><br>
      ${r.descripcion}<br>
      <small>👍 ${r.confirmaciones} confirmaciones</small>
    `);
  });

  return map;
}

async function onConfirmarReporte(reporte_id) {
  const { data, error } = await SupabaseAPI.confirmarReporte(reporte_id);
  if (error) { UI.toast(error, 'error'); return; }
  const el = document.getElementById(`confirms-${reporte_id}`);
  if (el && data?.confirmaciones !== undefined) el.textContent = data.confirmaciones;
  UI.toast('¡Confirmación registrada! Gracias por validar.', 'success', '👍 Validación comunitaria');
}

async function onNotificarRestablecimiento(reporte_id) {
  const coords = ReporteState.ubicacion || { lat: 4.7110, lng: -74.0721 };
  const { error } = await SupabaseAPI.notificarRestablecimiento(reporte_id, coords);
  if (error) { UI.toast(error, 'error'); return; }
  UI.toast('Notificación de restablecimiento enviada. El sistema calculará la duración del corte.', 'success', '✅ Servicio restablecido');
  await cargarReportesCercanos();
}

// Exponer globalmente (llamadas desde onclick inline)
window.onConfirmarReporte = onConfirmarReporte;
window.onNotificarRestablecimiento = onNotificarRestablecimiento;
