package com.servired.app.core.domain.model

/**
 * Resultado de registrar un reporte, enriquecido con metadatos de duplicidad
 * que devuelve la RPC registrar_reporte (Punto 5: ST_DWithin duplicates detection).
 */
data class ReporteCreado(
    /** UUID local del reporte (siempre presente) */
    val reporteId: String,

    /**
     * true si el ciudadano ya tenía un reporte del mismo servicio
     * a menos de 500 m en las últimas 4 horas. No se insertó un nuevo registro;
     * se retornó el existente.
     */
    val esDuplicado: Boolean = false,

    /**
     * UUID del incidente abierto (recibido / en_atencion) al que se vinculó
     * este reporte automáticamente por estar dentro de 500 m.
     * null si no había incidente cercano.
     */
    val incidenteCercanoId: String? = null,

    /**
     * Distancia en metros al centroide del incidente cercano.
     * null cuando incidenteCercanoId == null.
     */
    val incidenteCercanoDistancia: Double? = null
)
