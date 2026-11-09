// Edge Function: notify-outbox
// Consume el outbox de eventos y despacha notificaciones push via FCM.
// Se invoca desde un cron de Supabase (ej. cada 30s via pg_cron o scheduler externo).
// Reintentos con backoff exponencial ya viven en la DB (reclamar_eventos_outbox).

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FCM_SERVER_KEY = Deno.env.get("FCM_SERVER_KEY")!;
// URL del proyecto Firebase para FCM v1 API
const FCM_PROJECT_ID = Deno.env.get("FCM_PROJECT_ID")!;

// Número máximo de eventos por ejecución para evitar timeouts
const BATCH_LIMIT = 25;
const LEASE_SEGUNDOS = 120;

interface OutboxEvent {
  id: number;
  tipo: string;
  payload: Record<string, unknown>;
  intentos: number;
  correlation_id: string;
  lease_token: string;
  lease_hasta: string;
}

interface FcmTarget {
  fcm_token: string;
  ciudadano_id: string | null;
}

serve(async (_req) => {
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // Reclamar eventos pendientes con lease para procesamiento atómico
  const { data: eventos, error: claimError } = await supabase.rpc(
    "reclamar_eventos_outbox",
    { p_limite: BATCH_LIMIT, p_lease_segundos: LEASE_SEGUNDOS },
  );

  if (claimError) {
    console.error("Error reclamando eventos:", claimError.message);
    return new Response(JSON.stringify({ error: claimError.message }), {
      status: 500,
    });
  }

  if (!eventos || eventos.length === 0) {
    return new Response(JSON.stringify({ procesados: 0 }), { status: 200 });
  }

  const resultados = await Promise.allSettled(
    (eventos as OutboxEvent[]).map((evento) => procesarEvento(supabase, evento)),
  );

  const exitosos = resultados.filter((r) => r.status === "fulfilled").length;
  const fallidos = resultados.filter((r) => r.status === "rejected").length;

  return new Response(
    JSON.stringify({ procesados: exitosos, fallidos }),
    { status: 200 },
  );
});

async function procesarEvento(
  supabase: ReturnType<typeof createClient>,
  evento: OutboxEvent,
): Promise<void> {
  try {
    const targets = await resolverDestinatarios(supabase, evento);

    if (targets.length === 0) {
      // Sin destinatarios: marcar como procesado sin enviar
      await marcarProcesado(supabase, evento.id, evento.lease_token);
      return;
    }

    const fcmPayload = construirPayloadFcm(evento);
    const envios = await Promise.allSettled(
      targets.map((t) => enviarFcm(t.fcm_token, fcmPayload)),
    );

    const todosFallaron = envios.every((r) => r.status === "rejected");
    if (todosFallaron) {
      const primerError = (envios[0] as PromiseRejectedResult).reason;
      throw new Error(`Todos los envíos FCM fallaron: ${primerError}`);
    }

    // Registrar fallos de tokens individuales (tokens inválidos, etc.)
    for (let i = 0; i < envios.length; i++) {
      if (envios[i].status === "rejected") {
        const reason = (envios[i] as PromiseRejectedResult).reason;
        console.warn(
          `FCM falló para ciudadano ${targets[i].ciudadano_id}: ${reason}`,
        );
        await registrarFalloToken(supabase, targets[i].ciudadano_id, reason);
      }
    }

    await marcarProcesado(supabase, evento.id, evento.lease_token);
  } catch (err) {
    const mensaje = err instanceof Error ? err.message : String(err);
    await registrarFalloEvento(supabase, evento.id, evento.lease_token, mensaje);
    throw err;
  }
}

// Determina qué ciudadanos deben recibir la notificación según el tipo de evento
async function resolverDestinatarios(
  supabase: ReturnType<typeof createClient>,
  evento: OutboxEvent,
): Promise<FcmTarget[]> {
  const { tipo, payload } = evento;

  if (tipo === "reporte.estado_cambiado") {
    const reporteId = payload.reporte_id as string;
    const { data } = await supabase
      .from("reporte")
      .select("ciudadano_id, ciudadano:ciudadano_id(fcm_token)")
      .eq("id", reporteId)
      .single();

    if (!data?.ciudadano_id || !data?.ciudadano) return [];
    const token = (data.ciudadano as { fcm_token?: string }).fcm_token;
    if (!token) return [];
    return [{ fcm_token: token, ciudadano_id: data.ciudadano_id }];
  }

  if (tipo === "incidente.estado_cambiado") {
    // Notificar a todos los ciudadanos que reportaron en este incidente
    const incidenteId = payload.incidente_id as string;
    const { data } = await supabase
      .from("reporte")
      .select("ciudadano_id, ciudadano:ciudadano_id(fcm_token)")
      .eq("incidente_id", incidenteId)
      .not("ciudadano_id", "is", null);

    if (!data) return [];
    return data
      .filter((r) => (r.ciudadano as { fcm_token?: string })?.fcm_token)
      .map((r) => ({
        fcm_token: (r.ciudadano as { fcm_token: string }).fcm_token,
        ciudadano_id: r.ciudadano_id,
      }));
  }

  if (tipo === "denuncia.estado_cambiado") {
    // Las denuncias son anónimas: no hay token FCM asociado.
    // El denunciante usa el código de seguimiento para consultar estado.
    return [];
  }

  return [];
}

function construirPayloadFcm(
  evento: OutboxEvent,
): Record<string, unknown> {
  const { tipo, payload } = evento;
  const textos: Record<string, { title: string; body: string }> = {
    "reporte.creado": {
      title: "Reporte recibido",
      body: "Tu reporte fue registrado correctamente.",
    },
    "reporte.estado_cambiado": {
      title: "Estado de tu reporte actualizado",
      body: `Tu reporte cambió a: ${traducirEstado(payload.estado_nuevo as string)}`,
    },
    "incidente.estado_cambiado": {
      title: "Actualización del servicio",
      body: `El incidente está ahora en estado: ${traducirEstado(payload.estado_nuevo as string)}`,
    },
  };

  const texto = textos[tipo] ?? {
    title: "ServiRed",
    body: "Hay una actualización en tu solicitud.",
  };

  return {
    notification: { title: texto.title, body: texto.body },
    data: {
      tipo,
      correlation_id: evento.correlation_id,
      ...Object.fromEntries(
        Object.entries(payload).map(([k, v]) => [k, String(v)]),
      ),
    },
    android: {
      priority: "high",
      notification: { channel_id: "servired_notif" },
    },
  };
}

function traducirEstado(estado: string): string {
  const mapa: Record<string, string> = {
    recibido: "Recibido",
    vinculado: "Vinculado a incidente",
    descartado: "Descartado",
    en_atencion: "En atención",
    restablecido: "Restablecido",
    cerrado: "Cerrado",
    recibida: "Recibida",
    en_revision: "En revisión",
    validada: "Validada",
    descartada: "Descartada",
  };
  return mapa[estado] ?? estado;
}

async function enviarFcm(
  token: string,
  payload: Record<string, unknown>,
): Promise<void> {
  // FCM Legacy HTTP API (v1 requiere OAuth2; usar legacy con server key por simplicidad)
  const body = JSON.stringify({ to: token, ...payload });
  const res = await fetch("https://fcm.googleapis.com/fcm/send", {
    method: "POST",
    headers: {
      "Authorization": `key=${FCM_SERVER_KEY}`,
      "Content-Type": "application/json",
    },
    body,
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`FCM HTTP ${res.status}: ${text}`);
  }

  const json = await res.json();
  if (json.failure > 0) {
    const errorCode = json.results?.[0]?.error ?? "UNKNOWN";
    throw new Error(`FCM rechazó el token: ${errorCode}`);
  }
}

async function marcarProcesado(
  supabase: ReturnType<typeof createClient>,
  id: number,
  leaseToken: string,
): Promise<void> {
  const { error } = await supabase.rpc("marcar_evento_outbox_procesado", {
    p_id: id,
    p_lease_token: leaseToken,
  });
  if (error) {
    console.error(`No se pudo marcar evento ${id} como procesado:`, error.message);
  }
}

async function registrarFalloEvento(
  supabase: ReturnType<typeof createClient>,
  id: number,
  leaseToken: string,
  error: string,
): Promise<void> {
  const { error: rpcError } = await supabase.rpc(
    "registrar_fallo_evento_outbox",
    { p_id: id, p_lease_token: leaseToken, p_error: error },
  );
  if (rpcError) {
    console.error(`No se pudo registrar fallo del evento ${id}:`, rpcError.message);
  }
}

async function registrarFalloToken(
  supabase: ReturnType<typeof createClient>,
  ciudadanoId: string | null,
  razon: string,
): Promise<void> {
  if (!ciudadanoId) return;
  // Registra en audit_log para diagnóstico; no bloquea el flujo principal
  await supabase.from("audit_log").insert({
    actor_id: null,
    accion: "fcm_token_fallo",
    entidad: "ciudadano",
    entidad_id: ciudadanoId,
    despues: { razon },
  });
}

