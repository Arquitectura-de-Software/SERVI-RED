package com.servired.app.core.domain.model

data class Denuncia(
    val id: String,
    val clientRequestId: String,
    val servicio: TipoServicio,
    val municipioCodigo: String,
    val lat: Double?,
    val lng: Double?,
    val descripcion: String,
    val codigoSeguimiento: String,
    val seguimientoHash: String,
    val estado: String,
    val pendienteSync: Boolean,
    val creadoEn: Long,
    val intentos: Int
)
