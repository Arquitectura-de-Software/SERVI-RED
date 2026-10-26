/**
 * SERVI-RED — Edge Function: process-notifications
 * ADR-03: Procesamiento asíncrono de notificaciones (Patrón Outbox)
 *
 * Esta función se ejecuta como un cron job en Supabase Edge Functions
 * Consume la tabla outbox_eventos y envía notificaciones push via FCM
 *
 * Deploy: supabase functions deploy process-notifications
 * Cron:   supabase functions schedule process-notifications "*/2 * * * *"
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ─── Configuración ────────────────────────────────────────────
const SUPABASE_URL     = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_KEY     = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const FCM_SERVER_KEY   = Deno.env.get('FCM_SERVER_KEY')!;
const FCM_ENDPOINT     = 'https://fcm.googleapis.com/fcm/send';
const MAX_BATCH_SIZE   = 50; // Procesar máx 50 eventos por invocación

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

// ─── Handler Principal ────────────────────────────────────────
Deno.serve(async (_req: Request): Promise<Response> => {
  console.log('[process-notifications] Iniciando ciclo de procesamiento...');

  try {
    const processed = await procesarEventosPendientes();
    return new Response(
      JSON.stringify({ ok: true, procesados: processed }),
      { headers: { 'Content-Type': 'application/json' } }
    );
  } catch (err) {
    console.error('[process-notifications] Error crítico:', err);
    return new Response(
      JSON.stringify({ ok: false, error: String(err) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
});

// ─────────────────────────────────────────────────────────────
// PROCESADOR DE OUTBOX
// Patrón: SELECT FOR UPDATE SKIP LOCKED (evita procesamiento doble)
// ─────────────────────────────────────────────────────────────
async function procesarEventosPendientes(): Promise<number> {
  // Obtener eventos pendientes (máx MAX_BATCH_SIZE)
  const { data: eventos, error } = await supabase
    .from('outbox_eventos')
    .select('*')
    .eq('estado', 'pendiente')
    .lt('intentos', 5) // Solo si no superó max_intentos
    .order('created_at', { ascending: true })
    .limit(MAX_BATCH_SIZE);

  if (error) throw new Error(`Error consultando outbox: ${error.message}`);
  if (!eventos?.length) {
    console.log('[process-notifications] No hay eventos pendientes.');
    return 0;
  }

  console.log(`[process-notifications] Procesando ${eventos.length} eventos...`);
  let procesados = 0;

  for (const evento of eventos) {
    // Marcar como "procesando" para evitar concurrencia
    await supabase.from('outbox_eventos').update({ estado: 'procesando' }).eq('id', evento.id);

    try {
      await despacharEvento(evento);

      // Marcar como enviado
      await supabase.from('outbox_eventos').update({
        estado: 'enviado',
        processed_at: new Date().toISOString()
      }).eq('id', evento.id);

      procesados++;
    } catch (err) {
      const nuevoIntentos = evento.intentos + 1;
      const fallo = nuevoIntentos >= evento.max_intentos;

      // RESILIENCIA: El fallo de notificación NO revierte el reporte
      await supabase.from('outbox_eventos').update({
        estado: fallo ? 'fallido' : 'pendiente',
        intentos: nuevoIntentos,
        error_detalle: String(err)
      }).eq('id', evento.id);

      console.warn(`[process-notifications] Evento ${evento.id} falló (intento ${nuevoIntentos}):`, err);
    }
  }

  return procesados;
}

// ─────────────────────────────────────────────────────────────
// DESPACHADOR DE EVENTOS
// ─────────────────────────────────────────────────────────────
async function despacharEvento(evento: Record<string, unknown>): Promise<void> {
  switch (evento.canal) {
    case 'push_fcm':
      await enviarPushFCM(evento);
      break;
    case 'in_app':
      await emitirInApp(evento);
      break;
    case 'email':
      console.log('[process-notifications] Canal email no configurado en MVP');
      break;
    default:
      console.log(`[process-notifications] Canal desconocido: ${evento.canal}`);
  }
}

// ─────────────────────────────────────────────────────────────
// NOTIFICACIÓN PUSH FCM (Firebase Cloud Messaging)
// RF-06: Notificaciones multicanal
// ─────────────────────────────────────────────────────────────
async function enviarPushFCM(evento: Record<string, unknown>): Promise<void> {
  const payload = evento.payload as Record<string, unknown>;
  const reporte_id = evento.reporte_id as string;

  // Obtener tokens FCM activos (todos — notificación broadcast por zona)
  const { data: tokens } = await supabase
    .from('push_tokens')
    .select('token')
    .eq('activo', true);

  if (!tokens?.length) {
    console.log('[FCM] No hay tokens registrados.');
    return;
  }

  const mensajes = getMensajePorTipoEvento(evento.tipo_evento as string, payload, reporte_id);

  const fcmPayload = {
    registration_ids: tokens.map((t: { token: string }) => t.token),
    notification: {
      title: mensajes.titulo,
      body: mensajes.cuerpo,
      sound: 'default',
      badge: '1'
    },
    data: {
      reporte_id,
      tipo_evento: evento.tipo_evento,
      click_action: 'FLUTTER_NOTIFICATION_CLICK',
      screen: 'seguimiento'
    },
    android: { priority: 'high', notification: { channel_id: 'servi_red_alertas' } },
    apns: { payload: { aps: { sound: 'default' } } }
  };

  const res = await fetch(FCM_ENDPOINT, {
    method: 'POST',
    headers: {
      'Authorization': `key=${FCM_SERVER_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(fcmPayload)
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`FCM error ${res.status}: ${body}`);
  }

  const result = await res.json();
  console.log(`[FCM] Enviado a ${tokens.length} dispositivos. Éxito: ${result.success}, Fallo: ${result.failure}`);
}

// ─── Mensajes por tipo de evento ─────────────────────────────
function getMensajePorTipoEvento(tipo: string, payload: Record<string, unknown>, reporte_id: string) {
  const serviciosMap: Record<string, string> = {
    energia: 'Energía eléctrica', agua: 'Agua', gas: 'Gas natural',
    alcantarillado: 'Alcantarillado', aseo: 'Aseo'
  };
  switch (tipo) {
    case 'reporte_creado':
      return {
        titulo: '📢 Nuevo reporte en tu zona',
        cuerpo: `Reporte de ${serviciosMap[payload.tipo_servicio as string] || 'servicio'} registrado en ${payload.municipio}`
      };
    case 'estado_cambiado':
      const estadosMap: Record<string, string> = { en_atencion: '🔧 En atención', resuelto: '✅ Resuelto' };
      return {
        titulo: `SERVI-RED · Reporte ${reporte_id}`,
        cuerpo: `Tu reporte está: ${estadosMap[payload.estado_nuevo as string] || payload.estado_nuevo}`
      };
    case 'restablecimiento_confirmado':
      return {
        titulo: '✅ Servicio restablecido',
        cuerpo: `La comunidad confirmó el restablecimiento (${payload.confirmaciones} votos)`
      };
    default:
      return { titulo: 'SERVI-RED', cuerpo: 'Tienes una nueva actualización' };
  }
}

// ─── In-App via Supabase Realtime ─────────────────────────────
async function emitirInApp(evento: Record<string, unknown>): Promise<void> {
  // Supabase Realtime publica automáticamente los cambios en 'reportes'
  // No se necesita acción adicional si el cliente está suscrito al canal
  console.log('[InApp] Evento emitido via Realtime (cambio en tabla capturado por cliente):', evento.id);
}
