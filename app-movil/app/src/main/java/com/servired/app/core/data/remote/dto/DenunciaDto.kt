package com.servired.app.core.data.remote.dto

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class DenunciaDto(
    @SerialName("p_client_request_id") val clientRequestId: String,
    @SerialName("p_servicio_id") val servicioId: Int,
    @SerialName("p_municipio_codigo") val municipioCodigo: String,
    @SerialName("p_descripcion") val descripcion: String,
    @SerialName("p_codigo") val codigo: String,
    @SerialName("p_lat") val lat: Double? = null,
    @SerialName("p_lng") val lng: Double? = null,
    @SerialName("p_url_evidencia") val urlEvidencia: String? = null
)

@Serializable
data class ConsultaDenunciaDto(
    @SerialName("p_codigo") val codigo: String
)

@Serializable
data class ConsultaDenunciaResponseDto(
    val estado: String,
    @SerialName("creada_en") val creadaEn: String? = null
)
