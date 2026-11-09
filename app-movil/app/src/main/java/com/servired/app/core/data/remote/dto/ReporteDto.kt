package com.servired.app.core.data.remote.dto

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ReporteDto(
    @SerialName("client_request_id") val clientRequestId: String,
    @SerialName("servicio_id") val servicioId: Int,
    @SerialName("municipio_codigo") val municipioCodigo: String,
    val lat: Double,
    val lng: Double,
    val descripcion: String? = null,
    @SerialName("url_evidencia") val urlEvidencia: String? = null
)

@Serializable
data class ReporteResponseDto(
    val id: String,
    val estado: String
)
