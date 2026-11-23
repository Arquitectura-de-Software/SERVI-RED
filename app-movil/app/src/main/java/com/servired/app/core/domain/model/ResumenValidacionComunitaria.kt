package com.servired.app.core.domain.model

data class ResumenValidacionComunitaria(
    val incidenteId: String,
    val estadoIncidente: String,
    val inicioEn: String?,
    val restablecidoEn: String?,
    val duracionMinutos: Int,
    val totalRestablecido: Int,
    val totalSinServicio: Int,
    val miConfirmacion: String? // "restablecido" | "sin_servicio" | null
) {
    val duracionFormateada: String
        get() {
            if (duracionMinutos <= 0) return "En atención inicial"
            val horas = duracionMinutos / 60
            val minutos = duracionMinutos % 60
            return when {
                horas > 0 && minutos > 0 -> "${horas}h ${minutos}m"
                horas > 0 -> "${horas}h"
                else -> "${minutos}m"
            }
        }

    val totalVotos: Int
        get() = totalRestablecido + totalSinServicio

    val porcentajeRestablecido: Float
        get() = if (totalVotos > 0) (totalRestablecido.toFloat() / totalVotos.toFloat()) else 0f
}
