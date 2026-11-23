package com.servired.app.core.domain.repository

import com.servired.app.core.data.remote.dto.IncidenteCercanoDto
import com.servired.app.core.data.remote.dto.ResultadoConfirmacionDto
import com.servired.app.core.domain.model.Reporte
import com.servired.app.core.domain.model.ReporteCreado
import com.servired.app.core.domain.model.ResumenValidacionComunitaria
import com.servired.app.core.domain.model.TipoServicio
import kotlinx.coroutines.flow.Flow

interface ReporteRepository {
    fun observarTodos(): Flow<List<Reporte>>
    suspend fun crearReporte(
        servicio: TipoServicio,
        municipio: String,
        lat: Double,
        lng: Double,
        descripcion: String?,
        urlEvidencia: String? = null,
        inicioEstimado: String? = null
    ): Result<ReporteCreado>
    suspend fun consultarPorId(id: String): Result<Reporte>
    suspend fun consultarIncidentesCercanos(
        lat: Double,
        lng: Double,
        radioMetros: Double = 25000.0
    ): List<IncidenteCercanoDto>
    suspend fun registrarConfirmacion(
        incidenteId: String,
        tipo: String,
        lat: Double? = null,
        lng: Double? = null
    ): Result<ResultadoConfirmacionDto>
    suspend fun consultarResumenConfirmaciones(
        incidenteId: String
    ): Result<ResumenValidacionComunitaria>
}
