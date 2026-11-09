package com.servired.app.core.domain.repository

import com.servired.app.core.domain.model.Reporte
import com.servired.app.core.domain.model.TipoServicio
import kotlinx.coroutines.flow.Flow

interface ReporteRepository {
    fun observarTodos(): Flow<List<Reporte>>
    suspend fun crearReporte(
        servicio: TipoServicio,
        municipio: String,
        lat: Double,
        lng: Double,
        descripcion: String?
    ): Result<String>
    suspend fun consultarPorId(id: String): Result<Reporte>
}
