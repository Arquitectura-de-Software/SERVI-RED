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
        descripcion: String?,
        urlEvidencia: String?,
        inicioEstimado: String?
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
            pendienteSync = true,
            urlEvidencia = urlEvidencia,
            inicioEstimado = inicioEstimado
        )

        // Offline-first: siempre persiste localmente primero
        dao.insertOrIgnore(entity)

        if (connectivityObserver.isCurrentlyConnected()) {
            SupabaseClient.asegurarSesion(context)
            val dto = ReporteDto(
                clientRequestId = clientRequestId,
                servicioId = entity.servicioId,
                municipioCodigo = municipio,
                lat = lat,
                lng = lng,
                descripcion = descripcion,
                urlEvidencia = urlEvidencia,
                inicioEstimado = inicioEstimado
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

        SupabaseClient.asegurarSesion(context)
        return SupabaseClient.consultarReporte(id).map { dto ->
            Reporte(
                id = dto.id,
                clientRequestId = dto.clientRequestId,
                servicio = TipoServicio.entries.getOrNull(dto.servicioId - 1) ?: TipoServicio.ENERGIA,
                municipioCodigo = dto.municipioCodigo,
                lat = local?.lat ?: 0.0,
                lng = local?.lng ?: 0.0,
                descripcion = dto.descripcion,
                estado = dto.estado,
                pendienteSync = false,
                creadoEn = parsearFechaIso(dto.creadoEn),
                intentosSincronizacion = 0
            )
        }
    }

    private fun parsearFechaIso(fecha: String?): Long {
        if (fecha.isNullOrBlank()) return System.currentTimeMillis()
        return runCatching {
            java.time.Instant.parse(fecha).toEpochMilli()
        }.getOrDefault(System.currentTimeMillis())
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
        intentosSincronizacion = intentosSincronizacion,
        urlEvidencia = urlEvidencia,
        inicioEstimado = inicioEstimado
    )
}
