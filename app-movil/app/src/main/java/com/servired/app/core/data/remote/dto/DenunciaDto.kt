package com.servired.app.core.data.remote.dto

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class DenunciaDto(
    @SerialName("client_request_id") val clientRequestId: String,
    @SerialName("servicio_id") val servicioId: Int,
    @SerialName("municipio_codigo") val municipioCodigo: String,
    val lat: Double? = null,
    val lng: Double? = null,
    val descripcion: String,
    @SerialName("seguimiento_hash") val seguimientoHash: String
)

@Serializable
data class DenunciaResponseDto(
    val id: String,
    val estado: String
)
