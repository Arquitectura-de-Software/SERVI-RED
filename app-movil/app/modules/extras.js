/**
 * SERVI-RED — Módulo D: Denuncias Anónimas (RF-04)
 *             Módulo E: Seguimiento por ID (RF-05)
 *             Módulo F: Notificaciones (RF-06 + ADR-03)
 *             Módulo G: Gamificación y Voz
 */

// ─────────────────────────────────────────────────────────────
// MÓDULO D — Denuncias Anónimas de Fraude (RF-04)
// Sin datos personales — Privacidad por Diseño (ADR-02)
// ─────────────────────────────────────────────────────────────
function initDenunciaModule() {
  Modules['denuncia'] = {
    onEnter() {
      if (!DenunciaState.map) setTimeout(() => initMapaDenuncia(), 200);
    }
  };

  const DenunciaState = { map: null, marker: null, ubicacion: null };
  window.DenunciaState = DenunciaState;

  document.getElementById('btn-gps-denuncia')?.addEventListener('click', () => {
    if (!navigator.geolocation) { UI.toast('Geolocalización no disponible', 'error'); return; }
    navigator.geolocation.getCurrentPosition((pos) => {
      DenunciaState.ubicacion = { lat: pos.coords.latitude, lng: pos.coords.longitude };
      document.getElementById('gps-denuncia-status').textContent =
        `📍 ${DenunciaState.ubicacion.lat.toFixed(5)}, ${DenunciaState.ubicacion.lng.toFixed(5)}`;
      if (DenunciaState.map) DenunciaState.map.setView([DenunciaState.ubicacion.lat, DenunciaState.ubicacion.lng], 15);
      UI.toast('Ubicación aproximada capturada (privacidad preservada)', 'info');
    });
  });

  document.getElementById('form-denuncia')?.addEventListener('submit', async (e) => {
    e.preventDefault();

    const tipo = document.getElementById('denuncia-tipo')?.value;
    const descripcion = document.getElementById('denuncia-descripcion')?.value?.trim();
    const servicio = document.getElementById('denuncia-servicio')?.value;
    const municipio = document.getElementById('denuncia-municipio')?.value;

    if (!tipo || !descripcion || !servicio) {
      UI.toast('Completa los campos obligatorios', 'error');
      return;
    }
    if (descripcion.length < 15) {
      UI.toast('Describe el fraude con más detalle (mín. 15 caracteres)', 'error');
      return;
    }

    const submitBtn = document.getElementById('denuncia-submit-btn');
    UI.loading(submitBtn, true, 'Enviando denuncia...');

    // NUNCA se envía ningún dato personal — RF-04 + ADR-02
    const payload = {
      tipo_fraude: tipo,
      descripcion,
      servicio,
      municipio,
      // Coordenadas aproximadas (no exactas para preservar privacidad)
      latitud: DenunciaState.ubicacion
        ? Math.round(DenunciaState.ubicacion.lat * 100) / 100
        : null,
      longitud: DenunciaState.ubicacion
        ? Math.round(DenunciaState.ubicacion.lng * 100) / 100
        : null,
      // Sin user_id, sin email, sin nombre — Zero PII
    };

    const { data, error } = await SupabaseAPI.insertDenuncia(payload);
    UI.loading(submitBtn, false);

    if (error) {
      UI.toast(`Error al enviar: ${error}`, 'error');
      return;
    }

    // Mostrar confirmación anónima
    document.getElementById('denuncia-confirm-id').textContent = data.id || '—';
    UI.modal.open('modal-denuncia-confirm');
    document.getElementById('form-denuncia')?.reset();
    DenunciaState.ubicacion = null;
    document.getElementById('gps-denuncia-status').textContent = '';
  });
}

function initMapaDenuncia() {
  const el = document.getElementById('map-denuncia');
  if (!el || !window.DenunciaState) return;
  const state = window.DenunciaState;

  state.map = L.map('map-denuncia', { zoomControl: false, scrollWheelZoom: false })
    .setView([4.7110, -74.0721], 12);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png').addTo(state.map);

  state.map.on('click', (e) => {
    state.ubicacion = { lat: e.latlng.lat, lng: e.latlng.lng };
    if (state.marker) state.marker.setLatLng(e.latlng);
    else state.marker = L.marker(e.latlng).addTo(state.map);
    document.getElementById('gps-denuncia-status').textContent =
      `📍 Ubicación seleccionada (aproximada)`;
  });
}

// ─────────────────────────────────────────────────────────────
// MÓDULO E — Seguimiento por ID (RF-05)
// Consulta sin autenticación (RLS público en tabla)
// ─────────────────────────────────────────────────────────────
function initSeguimientoModule() {
  Modules['seguimiento'] = { onEnter() {} };

  document.getElementById('track-submit-btn')?.addEventListener('click', onBuscarReporte);
  document.getElementById('track-id-input')?.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') onBuscarReporte();
  });

  // Demo: mostrar ejemplos de IDs
  document.querySelectorAll('.demo-id-chip').forEach(chip => {
    chip.addEventListener('click', () => {
      document.getElementById('track-id-input').value = chip.textContent.trim();
      onBuscarReporte();
    });
  });
}

async function onBuscarReporte() {
  const id = document.getElementById('track-id-input')?.value?.trim();
  if (!id) { UI.toast('Ingresa el ID de trazabilidad', 'error'); return; }

  const btn = document.getElementById('track-submit-btn');
  UI.loading(btn, true, 'Buscando...');

  const resultEl = document.getElementById('track-result');
  resultEl.innerHTML = `
    <div class="card">
      <div class="skeleton" style="height:200px;border-radius:12px;"></div>
    </div>`;

  const { data: reporte, error } = await SupabaseAPI.getReportePorId(id);
  UI.loading(btn, false);

  if (error || !reporte) {
    resultEl.innerHTML = `
      <div class="empty-state">
        <div class="empty-state__icon">🔍</div>
        <div class="empty-state__title">Reporte no encontrado</div>
        <p class="section-subtitle">Verifica el ID de trazabilidad e intenta de nuevo.</p>
      </div>`;
    return;
  }

  renderTimelineReporte(reporte, resultEl);

  // Suscripción Realtime para actualizaciones en vivo (RF-06)
  SupabaseAPI.subscribeToReporte(reporte.id, (updatedReporte) => {
    renderTimelineReporte(updatedReporte, resultEl);
    UI.toast('Estado del reporte actualizado en tiempo real', 'info', '🔔 Actualización');
  });
}

function renderTimelineReporte(reporte, container) {
  const meta = UI.getServiceMeta(reporte.tipo_servicio);
  const allStates = ['recibido', 'en_atencion', 'resuelto'];
  const currentIdx = allStates.indexOf(reporte.estado);

  const timelineHTML = allStates.map((estado, idx) => {
    const timelineEv = reporte.timeline?.find(t => t.estado === estado);
    const isDone   = idx < currentIdx;
    const isActive = idx === currentIdx;
    const isPending = idx > currentIdx;
    const clase = isDone ? 'done' : isActive ? 'active' : 'pending';
    const icons = { recibido: '📥', en_atencion: '🔧', resuelto: '✅' };
    const labels = { recibido: 'Reporte Recibido', en_atencion: 'En Atención del Operador', resuelto: 'Servicio Restablecido' };

    return `
    <div class="timeline-item ${clase}">
      <div class="timeline-item__line">
        <div class="timeline-item__dot">${isDone ? '✓' : isActive ? icons[estado] : '○'}</div>
        ${idx < allStates.length - 1 ? '<div class="timeline-item__connector"></div>' : ''}
      </div>
      <div class="timeline-item__content">
        <div class="timeline-item__label">${labels[estado]}</div>
        ${timelineEv ? `<div class="timeline-item__time">${UI.formatTime(timelineEv.ts)}</div>` : ''}
        ${timelineEv?.nota ? `<div class="timeline-item__note">${timelineEv.nota}</div>` : ''}
        ${isPending ? '<div class="timeline-item__note" style="color:var(--text-muted)">Pendiente</div>' : ''}
      </div>
    </div>`;
  }).join('');

  container.innerHTML = `
    <div class="card card--gradient card--glow" style="gap:var(--sp-md);display:flex;flex-direction:column;">
      <div style="display:flex;justify-content:space-between;align-items:flex-start;flex-wrap:wrap;gap:8px">
        <div>
          <div style="font-size:.72rem;color:var(--text-muted);font-weight:600;text-transform:uppercase;letter-spacing:.5px">ID de Trazabilidad</div>
          <div style="font-family:var(--font-heading);font-size:1.1rem;font-weight:700;color:var(--text-primary)">${reporte.id}</div>
        </div>
        <span class="status-badge status-badge--${reporte.estado}">
          <span class="status-dot"></span>${UI.getStatusLabel(reporte.estado)}
        </span>
      </div>

      <div style="display:flex;align-items:center;gap:12px;padding:12px;background:var(--bg-secondary);border-radius:12px;border:1px solid var(--border)">
        <div style="width:40px;height:40px;border-radius:10px;background:color-mix(in srgb,${meta.color} 15%,transparent);display:flex;align-items:center;justify-content:center;font-size:20px">${meta.icon}</div>
        <div>
          <div style="font-size:.82rem;font-weight:700;color:${meta.color}">${meta.label}</div>
          <div style="font-size:.88rem;color:var(--text-primary)">${reporte.descripcion}</div>
          <div style="font-size:.74rem;color:var(--text-muted)">${reporte.municipio || ''} · ${UI.formatTime(reporte.created_at)}</div>
        </div>
      </div>

      <div>
        <div class="section-title" style="margin-bottom:12px">📋 Línea de Tiempo</div>
        <div class="timeline">
          ${timelineHTML}
        </div>
      </div>

      ${reporte.confirmaciones > 0 ? `
      <div style="display:flex;align-items:center;gap:8px;padding:10px 14px;background:rgba(104,211,145,.08);border:1px solid rgba(104,211,145,.2);border-radius:10px">
        <span style="font-size:18px">👥</span>
        <span style="font-size:.83rem;color:var(--status-resuelto)"><b>${reporte.confirmaciones} ciudadanos</b> confirmaron este reporte</span>
      </div>` : ''}
    </div>`;
}

// ─────────────────────────────────────────────────────────────
// MÓDULO F — Notificaciones (RF-06 + ADR-03)
// Procesamiento asíncrono — Patrón Outbox
// ─────────────────────────────────────────────────────────────
const NotificacionesManager = {
  inAppChannel: null,

  // Simular suscripción a Supabase Realtime (WebSocket)
  iniciar(reporte_id) {
    console.log(`[Realtime] Suscribiendo a reporte: ${reporte_id}`);
    // En producción:
    // this.inAppChannel = supabaseClient
    //   .channel(`reporte-${reporte_id}`)
    //   .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'reportes', filter: `id=eq.${reporte_id}` }, payload => {
    //     this.onCambioEstado(payload.new);
    //   })
    //   .subscribe();
  },

  onCambioEstado(reporte) {
    UI.toast(`Tu reporte cambió a: ${UI.getStatusLabel(reporte.estado)}`, 'info', '🔔 Actualización');
    // Actualizar badge en nav
    const badge = document.querySelector('.nav-item[data-screen="seguimiento"] .badge');
    if (badge) badge.style.display = 'block';
  },

  // Push externo (FCM) — se configura en Edge Function serverless
  registrarTokenFCM(token) {
    console.log('[FCM] Registrando token para notificaciones push:', token);
    // POST a /rest/v1/push_tokens con el token del dispositivo
    // La Edge Function consume la tabla outbox_eventos y llama a FCM API
  }
};

window.NotificacionesManager = NotificacionesManager;

// ─────────────────────────────────────────────────────────────
// MÓDULO G — Gamificación + Voz (Persona 3)
// ─────────────────────────────────────────────────────────────
function initPerfilModule() {
  Modules['perfil'] = {
    onEnter() {
      renderPerfil();
    }
  };
}

function renderPerfil() {
  const stats = SupabaseAPI.getGamificacionPerfil();
  const allInsignias = MockDB.gamificacion.insignias;

  // Estadísticas
  document.getElementById('stat-reportes').textContent = stats.reportes_enviados || 0;
  document.getElementById('stat-confirmaciones').textContent = stats.confirmaciones_dadas || 0;
  document.getElementById('stat-insignias').textContent = stats.insignias_obtenidas?.length || 0;

  // Insignias
  const badgeGrid = document.getElementById('badge-grid');
  if (!badgeGrid) return;

  badgeGrid.innerHTML = allInsignias.map(ins => {
    const earned = stats.insignias_obtenidas?.includes(ins.id);
    return `
    <div class="badge-card ${earned ? 'earned' : ''}">
      <div class="badge-icon">${ins.icono}</div>
      <div class="badge-name">${ins.nombre}</div>
      <div class="badge-desc">${ins.descripcion}</div>
      ${earned ? '<span style="font-size:.7rem;color:var(--status-resuelto);font-weight:700">✓ Obtenida</span>' : '<span style="font-size:.7rem;color:var(--text-muted)">Bloqueada</span>'}
    </div>`;
  }).join('');

  // Mostrar cola offline si hay pendientes
  const queue = OfflineQueue.getAll();
  const queueEl = document.getElementById('offline-queue-count');
  if (queueEl) {
    queueEl.textContent = queue.length > 0
      ? `${queue.length} reporte(s) pendientes de sincronizar`
      : 'Todo sincronizado ✓';
    queueEl.style.color = queue.length > 0 ? 'var(--status-offline)' : 'var(--status-resuelto)';
  }
}

// ─────────────────────────────────────────────────────────────
// MÓDULO G — Reporte por Voz (Inclusividad)
// Web Speech API
// ─────────────────────────────────────────────────────────────
function initVoiceModule() {
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  const voiceBtn = document.getElementById('voice-report-btn');
  const voiceStatus = document.getElementById('voice-status');
  const voiceTranscript = document.getElementById('voice-transcript');

  if (!SpeechRecognition || !voiceBtn) {
    if (voiceBtn) {
      voiceBtn.disabled = true;
      voiceBtn.title = 'Reconocimiento de voz no disponible en este navegador';
    }
    return;
  }

  let recognition = null;
  let isRecording = false;

  voiceBtn.addEventListener('click', () => {
    if (isRecording) {
      recognition?.stop();
      return;
    }

    recognition = new SpeechRecognition();
    recognition.lang = 'es-CO';
    recognition.continuous = false;
    recognition.interimResults = true;
    recognition.maxAlternatives = 1;

    recognition.onstart = () => {
      isRecording = true;
      voiceBtn.classList.add('recording');
      if (voiceStatus) voiceStatus.textContent = '🎙️ Escuchando... Describe el problema';
    };

    recognition.onresult = (event) => {
      const transcript = Array.from(event.results)
        .map(r => r[0].transcript).join('');
      if (voiceTranscript) voiceTranscript.value = transcript;

      // Auto-rellenar descripción del formulario de reporte
      const descEl = document.getElementById('reporte-descripcion');
      if (descEl) descEl.value = transcript;

      // Detectar tipo de servicio por voz
      const lower = transcript.toLowerCase();
      const serviceMap = {
        'luz': 'energia', 'energía': 'energia', 'electricidad': 'energia',
        'apagón': 'energia', 'luz se fue': 'energia',
        'agua': 'agua', 'acueducto': 'agua', 'grifo': 'agua',
        'gas': 'gas', 'fuga': 'gas',
        'alcantarillado': 'alcantarillado', 'aguas negras': 'alcantarillado',
        'basura': 'aseo', 'aseo': 'aseo', 'recolección': 'aseo'
      };

      for (const [keyword, servicio] of Object.entries(serviceMap)) {
        if (lower.includes(keyword)) {
          const chip = document.querySelector(`#screen-reporte .service-chip[data-servicio="${servicio}"]`);
          if (chip && !chip.classList.contains('selected')) {
            chip.click();
            UI.toast(`Servicio detectado por voz: ${UI.getServiceMeta(servicio).label}`, 'info');
          }
          break;
        }
      }
    };

    recognition.onerror = (event) => {
      isRecording = false;
      voiceBtn.classList.remove('recording');
      if (voiceStatus) voiceStatus.textContent = '❌ Error de reconocimiento. Intenta de nuevo.';
      UI.toast('Error en reconocimiento de voz', 'error');
    };

    recognition.onend = () => {
      isRecording = false;
      voiceBtn.classList.remove('recording');
      if (voiceStatus) voiceStatus.textContent = '✅ Listo. Puedes editar el texto antes de enviar.';
      // Si capturó texto, navegar al formulario de reporte
      if (voiceTranscript?.value) {
        setTimeout(() => Router.navigate('reporte'), 800);
      }
    };

    recognition.start();
  });
}

// Exponer para uso global
window.onBuscarReporte = onBuscarReporte;
window.renderPerfil = renderPerfil;
