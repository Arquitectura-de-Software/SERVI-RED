package com.servired.app.core.notifications

import io.ktor.client.HttpClient
import io.ktor.client.engine.android.Android
import io.ktor.client.plugins.websocket.WebSockets
import io.ktor.client.plugins.websocket.webSocket
import io.ktor.websocket.Frame
import io.ktor.websocket.readText
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Escucha cambios en la tabla `reporte` vía Supabase Realtime (WebSocket)
class InAppNotificationManager(
    private val supabaseUrl: String,
    private val supabaseAnonKey: String
) {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _eventos = MutableSharedFlow<RealtimeEvento>()
    val eventos: SharedFlow<RealtimeEvento> = _eventos.asSharedFlow()

    private val wsClient = HttpClient(Android) {
        install(WebSockets)
    }

    // Inicia la escucha para el ciudadano con el id dado
    fun iniciarEscucha(ciudadanoId: String) {
        scope.launch {
            val wsUrl = supabaseUrl
                .replace("https://", "wss://")
                .replace("http://", "ws://")
                .plus("/realtime/v1/websocket?apikey=$supabaseAnonKey&vsn=1.0.0")

            runCatching {
                wsClient.webSocket(wsUrl) {
                    // Suscripción al canal de la tabla reporte filtrado por ciudadano_id
                    val subscribeMsg = """
                        {
                          "topic": "realtime:public:reporte:ciudadano_id=eq.$ciudadanoId",
                          "event": "phx_join",
                          "payload": {},
                          "ref": "1"
                        }
                    """.trimIndent()
                    send(Frame.Text(subscribeMsg))

                    for (frame in incoming) {
                        if (frame is Frame.Text) {
                            procesarMensaje(frame.readText())
                        }
                    }
                }
            }
        }
    }

    private suspend fun procesarMensaje(raw: String) {
        runCatching {
            val json = Json { ignoreUnknownKeys = true }
            val obj = json.parseToJsonElement(raw).jsonObject
            val evento = obj["event"]?.jsonPrimitive?.content ?: return
            val payload = obj["payload"]?.jsonObject ?: return
            val record = payload["record"]?.jsonObject ?: return
            val reporteId = record["id"]?.jsonPrimitive?.content ?: return
            val estado = record["estado"]?.jsonPrimitive?.content ?: return
            _eventos.emit(RealtimeEvento(evento = evento, reporteId = reporteId, estado = estado))
        }
    }

    data class RealtimeEvento(
        val evento: String,
        val reporteId: String,
        val estado: String
    )
}
