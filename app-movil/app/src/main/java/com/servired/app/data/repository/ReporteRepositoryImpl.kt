package com.servired.app.data.repository

import com.servired.app.core.data.local.db.AppDatabase
import com.servired.app.core.data.local.entity.ReporteEntity
import com.servired.app.core.data.remote.SupabaseClient
import com.servired.app.core.data.remote.dto.ReporteDto
import com.servired.app.core.data.sync.OutboxSyncWorker
import com.servired.app.core.domain.model.Reporte
import com.servired.app.core.domain.model.TipoServicio
import com.servired.app.core.domain.repository.ReporteRepository
import com.servired.app.core.network.ConnectivityObserver
import android.content.Context
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.util.UUID

class ReporteRepositoryImpl(
    private val context: Context,
    private val db: AppDatabase,
    private val connectivityObserver: ConnectivityObserver
) : ReporteRepository {

    private val dao = db.reporteDao()

    // Umbral para considerar datos frescos (5 minutos)
    private val FRESHNESS_MS = 5 * 60 * 1000L

    override fun observarTodos(): Flow<List<Reporte>> {
        return dao.getAll().map { list -> list.map { it.toDomain() } }
    }

    override suspend fun crearReporte(
        servicio: TipoServicio,
        municipio: String,
        lat: Double,
        lng: Double,
        descripcion: String?
    ): Result<String> {
        val id = UUID.randomUUID().toString()
        val clientRequestId = UUID.randomUUID().toString()

        val entity = ReporteEntity(
            id = id,
            clientRequestId = clientRequestId,
            servicioId = servicio.ordinal + 1,
            municipioCodigo = municipio,
            lat = lat,
            lng = lng,
            descripcion = descripcion,
            estado = "recibido",
            pendienteSync = true
        )

        // Offline-first: siempre persiste localmente primero
        dao.insertOrIgnore(entity)

        if (connectivityObserver.isCurrentlyConnected()) {
            val dto = ReporteDto(
                clientRequestId = clientRequestId,
                servicioId = entity.servicioId,
                municipioCodigo = municipio,
                lat = lat,
                lng = lng,
                descripcion = descripcion
            )
            val resultado = SupabaseClient.registrarReporte(dto)
            if (resultado.isSuccess) {
                dao.marcarSincronizado(id)
                resultado.getOrNull()?.estado?.let { dao.updateEstado(id, it) }
            } else {
                OutboxSyncWorker.enqueue(context)
            }
        } else {
            OutboxSyncWorker.enqueue(context)
        }

        return Result.success(id)
    }

    override suspend fun consultarPorId(id: String): Result<Reporte> {
        val local = dao.getById(id)
        val ahora = System.currentTimeMillis()

        if (local != null && (ahora - local.creadoEn) < FRESHNESS_MS) {
            return Result.success(local.toDomain())
        }

        if (!connectivityObserver.isCurrentlyConnected()) {
            return if (local != null) Result.success(local.toDomain())
            else Result.failure(Exception("Sin conexión y sin datos locales"))
        }

        return SupabaseClient.consultarReporte(id).map { dto ->
            Reporte(
                id = id,
                clientRequestId = "",
                servicio = TipoServicio.entries.getOrNull(dto.servicioId - 1) ?: TipoServicio.ENERGIA,
                municipioCodigo = dto.municipioCodigo,
                lat = dto.lat,
                lng = dto.lng,
                descripcion = dto.descripcion,
                estado = "recibido",
                pendienteSync = false,
                creadoEn = System.currentTimeMillis(),
                intentosSincronizacion = 0
            )
        }
    }

    private fun ReporteEntity.toDomain() = Reporte(
        id = id,
        clientRequestId = clientRequestId,
        servicio = TipoServicio.entries.getOrNull(servicioId - 1) ?: TipoServicio.ENERGIA,
        municipioCodigo = municipioCodigo,
        lat = lat,
        lng = lng,
        descripcion = descripcion,
        estado = estado,
        pendienteSync = pendienteSync,
        creadoEn = creadoEn,
        intentosSincronizacion = intentosSincronizacion
    )
}
