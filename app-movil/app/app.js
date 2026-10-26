/**
 * SERVI-RED — App Controller (Navigation + Module Router)
 * Maneja el sistema de pantallas, navegación inferior y utilidades globales
 */

// ─────────────────────────────────────────────────────────────
// UTILIDADES UI
// ─────────────────────────────────────────────────────────────
const UI = {
  toast(msg, type = 'info', title = '') {
    const container = document.getElementById('toast-container');
    const icons = { success: '✅', error: '❌', info: 'ℹ️', warning: '⚠️' };
    const toast = document.createElement('div');
    toast.className = `toast toast--${type}`;
    toast.innerHTML = `
      <div class="toast__icon">${icons[type] || 'ℹ️'}</div>
      <div class="toast__body">
        ${title ? `<div class="toast__title">${title}</div>` : ''}
        <div class="toast__msg">${msg}</div>
      </div>
    `;
    container.appendChild(toast);
    setTimeout(() => {
      toast.style.opacity = '0';
      toast.style.transform = 'translateY(-10px)';
      toast.style.transition = 'all .3s ease';
      setTimeout(() => toast.remove(), 300);
    }, 3500);
  },

  modal: {
    open(id) {
      const el = document.getElementById(id);
      if (el) { el.classList.add('open'); document.body.style.overflow = 'hidden'; }
    },
    close(id) {
      const el = document.getElementById(id);
      if (el) { el.classList.remove('open'); document.body.style.overflow = ''; }
    }
  },

  loading(btn, isLoading, text = null) {
    if (!btn) return;
    if (isLoading) {
      btn._originalText = btn.innerHTML;
      btn.disabled = true;
      btn.innerHTML = `<div class="spinner" style="width:18px;height:18px;border-width:2px"></div> ${text || 'Enviando...'}`;
    } else {
      btn.disabled = false;
      btn.innerHTML = btn._originalText || text || 'Enviar';
    }
  },

  formatTime(isoStr) {
    const d = new Date(isoStr);
    const now = new Date();
    const diff = Math.floor((now - d) / 60000);
    if (diff < 1) return 'Hace un momento';
    if (diff < 60) return `Hace ${diff} min`;
    if (diff < 1440) return `Hace ${Math.floor(diff/60)}h`;
    return d.toLocaleDateString('es-CO', { month: 'short', day: 'numeric' });
  },

  getServiceMeta(tipo) {
    const map = {
      energia:        { label: 'Energía Eléctrica', icon: '⚡', color: '#F6AD55' },
      agua:           { label: 'Agua / Acueducto',   icon: '💧', color: '#63B3ED' },
      gas:            { label: 'Gas Natural',         icon: '🔥', color: '#68D391' },
      alcantarillado: { label: 'Alcantarillado',      icon: '🚿', color: '#9F7AEA' },
      aseo:           { label: 'Aseo / Basuras',      icon: '🗑️', color: '#FC8181' },
    };
    return map[tipo] || { label: tipo, icon: '❓', color: '#8B96B8' };
  },

  getStatusLabel(estado) {
    const map = {
      recibido: 'Recibido', en_atencion: 'En Atención',
      resuelto: 'Resuelto', en_cola_offline: 'Sin Conexión',
      en_moderacion: 'En Moderación'
    };
    return map[estado] || estado;
  }
};

// ─────────────────────────────────────────────────────────────
// ROUTER / NAVEGACIÓN PRINCIPAL
// ─────────────────────────────────────────────────────────────
const Router = {
  current: 'home',
  history: [],

  navigate(screenId, { back = false, data = null } = {}) {
    const prevScreen = document.querySelector('.screen.active');
    const nextScreen = document.getElementById(`screen-${screenId}`);
    if (!nextScreen || screenId === this.current) return;

    if (!back) this.history.push(this.current);
    this.current = screenId;

    if (prevScreen) prevScreen.classList.remove('active');
    nextScreen.classList.add('active');
    nextScreen.style.animationName = back ? 'screenInLeft' : 'screenIn';

    // Update nav items
    document.querySelectorAll('.nav-item').forEach(item => {
      item.classList.toggle('active', item.dataset.screen === screenId);
    });

    // Lifecycle hook
    if (Modules[screenId]?.onEnter) Modules[screenId].onEnter(data);

    // Scroll to top
    nextScreen.scrollTop = 0;
  },

  back() {
    if (this.history.length > 0) {
      this.navigate(this.history.pop(), { back: true });
    } else {
      this.navigate('home');
    }
  }
};

// ─────────────────────────────────────────────────────────────
// MODULOS (lifecycle callbacks por pantalla)
// ─────────────────────────────────────────────────────────────
const Modules = {};

// ─────────────────────────────────────────────────────────────
// INICIALIZACIÓN PRINCIPAL
// ─────────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {

  // ── Splash screen ────────────────────────────────────────
  // Mostrar home de inmediato para que sea visible, luego mostrar splash encima
  Router.navigate('home');
  setTimeout(() => {
    document.getElementById('splash-screen').classList.add('hidden');
  }, 1800);

  // ── Navegación inferior ──────────────────────────────────
  document.querySelectorAll('.nav-item[data-screen]').forEach(item => {
    item.addEventListener('click', () => Router.navigate(item.dataset.screen));
  });

  // ── Botones de retroceso ─────────────────────────────────
  document.querySelectorAll('[data-back]').forEach(btn => {
    btn.addEventListener('click', () => Router.back());
  });

  // ── Navegación por links con data-goto ───────────────────
  document.querySelectorAll('[data-goto]').forEach(el => {
    el.addEventListener('click', () => Router.navigate(el.dataset.goto));
  });

  // ── Cerrar modales ───────────────────────────────────────
  document.querySelectorAll('[data-close-modal]').forEach(btn => {
    btn.addEventListener('click', () => UI.modal.close(btn.dataset.closeModal));
  });
  document.querySelectorAll('.modal-overlay').forEach(overlay => {
    overlay.addEventListener('click', (e) => {
      if (e.target === overlay) UI.modal.close(overlay.id);
    });
  });

  // ── Estado de conexión ───────────────────────────────────
  const offlineBanner = document.getElementById('offline-banner');
  function updateConnectionStatus() {
    offlineBanner.classList.toggle('visible', !navigator.onLine);
  }
  updateConnectionStatus();
  document.addEventListener('servi-red:online', () => {
    updateConnectionStatus();
    UI.toast('Conexión restaurada. Enviando reportes pendientes...', 'success', '🟢 En línea');
  });
  document.addEventListener('servi-red:offline', () => {
    updateConnectionStatus();
    UI.toast('Sin conexión. Los reportes se guardarán localmente.', 'warning', '🔴 Sin red');
  });

  // ── Inicializar módulos ──────────────────────────────────
  initHomeModule();
  initReporteModule();
  initComunidadModule();
  initDenunciaModule();
  initSeguimientoModule();
  initPerfilModule();

  // ── Procesar cola offline si hay conexión ─────────────────
  if (navigator.onLine) OfflineQueue.processAll();

  // Registrar Voice Report (Módulo G)
  initVoiceModule();
});

// ─────────────────────────────────────────────────────────────
// HOME MODULE
// ─────────────────────────────────────────────────────────────
function initHomeModule() {
  Modules['home'] = {
    onEnter() {
      const listEl = document.getElementById('home-recent-list');
      renderRecentReports(listEl);
    }
  };

  document.getElementById('home-btn-reportar')?.addEventListener('click', () => Router.navigate('reporte'));
  document.getElementById('home-btn-seguir')?.addEventListener('click', () => Router.navigate('seguimiento'));

  // Quick actions
  document.querySelectorAll('.quick-action[data-goto]').forEach(el => {
    el.addEventListener('click', () => Router.navigate(el.dataset.goto));
  });
}

function renderRecentReports(container) {
  if (!container) return;
  const reportes = MockDB.reportes.slice(0, 3);

  if (reportes.length === 0) {
    container.innerHTML = `
      <div class="empty-state">
        <div class="empty-state__icon">📭</div>
        <div class="empty-state__title">No hay reportes recientes</div>
      </div>`;
    return;
  }

  container.innerHTML = reportes.map(r => {
    const meta = UI.getServiceMeta(r.tipo_servicio);
    return `
    <div class="report-card" onclick="Router.navigate('seguimiento'); document.getElementById('track-id-input').value='${r.id}'; setTimeout(() => document.getElementById('track-submit-btn').click(), 300)">
      <div class="report-card__icon" style="background:color-mix(in srgb, ${meta.color} 15%, transparent);">
        ${meta.icon}
      </div>
      <div class="report-card__body">
        <div class="report-card__type" style="color:${meta.color}">${meta.label}</div>
        <div class="report-card__desc">${r.descripcion}</div>
        <div class="report-card__meta">
          <span class="status-badge status-badge--${r.estado}">
            <span class="status-dot"></span>${UI.getStatusLabel(r.estado)}
          </span>
          <span>·</span>
          <span>${UI.formatTime(r.created_at)}</span>
          <span>·</span>
          <span>👍 ${r.confirmaciones}</span>
        </div>
      </div>
    </div>`;
  }).join('');
}

// Exportar para acceso global
window.Router = Router;
window.UI = UI;
window.Modules = Modules;
window.renderRecentReports = renderRecentReports;
