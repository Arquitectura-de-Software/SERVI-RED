package com.servired.app.core.data.remote.dto

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ReporteDto(
    @SerialName("p_client_request_id") val clientRequestId: String,
    @SerialName("p_servicio_id") val servicioId: Int,
    @SerialName("p_municipio_codigo") val municipioCodigo: String,
    @SerialName("p_lat") val lat: Double,
    @SerialName("p_lng") val lng: Double,
    @SerialName("p_descripcion") val descripcion: String? = null,
    @SerialName("p_url_evidencia") val urlEvidencia: String? = null,
    @SerialName("p_inicio_estimado") val inicioEstimado: String? = null
)

@Serializable
data class ReporteResponseDto(
    @SerialName("reporte_id") val reporteId: String = "",
    val estado: String = "",
    @SerialName("creado_en") val creadoEn: String? = null,
    @SerialName("correlation_id") val correlationId: String? = null,
    // ── Punto 5: Detección de duplicados ──────────────────────────────────────
    @SerialName("es_duplicado") val esDuplicado: Boolean = false,
    @SerialName("incidente_cercano_id") val incidenteCercanoId: String? = null,
    @SerialName("incidente_cercano_distancia") val incidenteCercanoDistancia: Double? = null
) {
    // Getter de conveniencia para compatibilidad con código existente que use dto.id
    val id: String get() = reporteId
}

@Serializable
data class ReporteDetalleDto(
    val id: String,
    @SerialName("client_request_id") val clientRequestId: String = "",
    @SerialName("servicio_id") val servicioId: Int = 1,
    @SerialName("municipio_codigo") val municipioCodigo: String = "",
    val descripcion: String? = null,
    val estado: String = "recibido",
    @SerialName("url_evidencia") val urlEvidencia: String? = null,
    @SerialName("inicio_estimado") val inicioEstimado: String? = null,
    @SerialName("creado_en") val creadoEn: String? = null,
    @SerialName("incidente_id") val incidenteId: String? = null
)

@Serializable
data class ConsultaCercanosDto(
    @SerialName("p_lat") val lat: Double,
    @SerialName("p_lng") val lng: Double,
    @SerialName("p_radio_metros") val radioMetros: Double = 25000.0
)

@Serializable
data class IncidenteCercanoDto(
    val id: String,
    @SerialName("servicio_id") val servicioId: Int = 1,
    @SerialName("municipio_codigo") val municipioCodigo: String? = null,
    val lat: Double,
    val lng: Double,
    val estado: String = "recibido",
    val prioridad: Int = 3,
    @SerialName("creado_en") val creadoEn: String? = null,
    @SerialName("distancia_metros") val distanciaMetros: Double? = null
)

@Serializable
data class ConfirmacionCiudadanaDto(
    @SerialName("p_incidente_id") val incidenteId: String,
    @SerialName("p_tipo") val tipo: String, // "restablecido" | "sin_servicio"
    @SerialName("p_lat") val lat: Double? = null,
    @SerialName("p_lng") val lng: Double? = null
)

@Serializable
data class ResultadoConfirmacionDto(
    @SerialName("confirmacion_id") val confirmacionId: String = "",
    @SerialName("incidente_id") val incidenteId: String = "",
    @SerialName("estado_incidente") val estadoIncidente: String = "",
    @SerialName("total_restablecido") val totalRestablecido: Int = 0,
    @SerialName("total_sin_servicio") val totalSinServicio: Int = 0,
    @SerialName("duracion_minutos") val duracionMinutos: Int = 0,
    @SerialName("umbral_alcanzado") val umbralAlcanzado: Boolean = false,
    val mensaje: String = ""
)

@Serializable
data class ConsultaResumenDto(
    @SerialName("p_incidente_id") val incidenteId: String
)

@Serializable
data class ResumenConfirmacionesDto(
    @SerialName("incidente_id") val incidenteId: String = "",
    @SerialName("estado_incidente") val estadoIncidente: String = "",
    @SerialName("inicio_en") val inicioEn: String? = null,
    @SerialName("restablecido_en") val restablecidoEn: String? = null,
    @SerialName("duracion_minutos") val duracionMinutos: Int = 0,
    @SerialName("total_restablecido") val totalRestablecido: Int = 0,
    @SerialName("total_sin_servicio") val totalSinServicio: Int = 0,
    @SerialName("mi_confirmacion") val miConfirmacion: String? = null
)
