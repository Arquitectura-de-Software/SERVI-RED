package com.servired.app.feature.mapa

import android.location.Location
import com.servired.app.core.data.remote.dto.IncidenteCercanoDto
import com.servired.app.core.domain.model.Reporte
import com.servired.app.core.domain.model.TipoServicio

data class ElementoMapa(
    val id: String,
    val esIncidente: Boolean,
    val servicio: TipoServicio,
    val lat: Double,
    val lng: Double,
    val estado: String,
    val descripcion: String?,
    val fecha: Long,
    val municipio: String? = null,
    val distanciaMetros: Float? = null
) {
    val titulo: String
        get() = if (esIncidente) "Incidente de ${servicio.name.lowercase().replaceFirstChar { it.uppercase() }}"
        else "Reporte de ${servicio.name.lowercase().replaceFirstChar { it.uppercase() }}"
}

fun Reporte.toElementoMapa(userLat: Double? = null, userLng: Double? = null): ElementoMapa {
    val distancia = if (userLat != null && userLng != null) {
        val result = FloatArray(1)
        Location.distanceBetween(userLat, userLng, lat, lng, result)
        result[0]
    } else null

    return ElementoMapa(
        id = id,
        esIncidente = false,
        servicio = servicio,
        lat = lat,
        lng = lng,
        estado = estado,
        descripcion = descripcion,
        fecha = creadoEn,
        municipio = municipioCodigo,
        distanciaMetros = distancia
    )
}

fun IncidenteCercanoDto.toElementoMapa(userLat: Double? = null, userLng: Double? = null): ElementoMapa {
    val servicioEnum = when (servicioId) {
        1 -> TipoServicio.ENERGIA
        2 -> TipoServicio.GAS
        3 -> TipoServicio.ACUEDUCTO
        4 -> TipoServicio.ALCANTARILLADO
        5 -> TipoServicio.ASEO
        else -> TipoServicio.ACUEDUCTO
    }
    val distancia = distanciaMetros?.toFloat() ?: if (userLat != null && userLng != null) {
        val result = FloatArray(1)
        Location.distanceBetween(userLat, userLng, lat, lng, result)
        result[0]
    } else null

    return ElementoMapa(
        id = id,
        esIncidente = true,
        servicio = servicioEnum,
        lat = lat,
        lng = lng,
        estado = estado,
        descripcion = "Incidente agrupado de red (prioridad $prioridad)",
        fecha = System.currentTimeMillis(),
        municipio = municipioCodigo,
        distanciaMetros = distancia
    )
}
