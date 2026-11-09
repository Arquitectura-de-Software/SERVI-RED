package com.servired.app.data.repository

import android.content.Context
import com.servired.app.core.data.local.db.AppDatabase
import com.servired.app.core.data.local.entity.DenunciaEntity
import com.servired.app.core.data.remote.SupabaseClient
import com.servired.app.core.data.remote.dto.DenunciaDto
import com.servired.app.core.data.sync.OutboxSyncWorker
import com.servired.app.core.domain.model.Denuncia
import com.servired.app.core.domain.model.TipoServicio
import com.servired.app.core.domain.repository.DenunciaRepository
import com.servired.app.core.network.ConnectivityObserver
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.security.MessageDigest
import java.util.UUID

class DenunciaRepositoryImpl(
    private val context: Context,
    private val db: AppDatabase,
    private val connectivityObserver: ConnectivityObserver
) : DenunciaRepository {

    private val dao = db.denunciaDao()

    override suspend fun enviarDenuncia(
        servicio: TipoServicio,
        municipio: String,
        descripcion: String,
        lat: Double?,
        lng: Double?
    ): Result<String> {
        // Genera el código plano que el usuario debe guardar
        val codigoSeguimiento = UUID.randomUUID().toString()
        val seguimientoHash = sha256(codigoSeguimiento)
        val id = UUID.randomUUID().toString()
        val clientRequestId = UUID.randomUUID().toString()

        val entity = DenunciaEntity(
            id = id,
            clientRequestId = clientRequestId,
            servicioId = servicio.ordinal + 1,
            municipioCodigo = municipio,
            lat = lat,
            lng = lng,
            descripcion = descripcion,
            codigoSeguimiento = codigoSeguimiento,
            seguimientoHash = seguimientoHash,
            estado = "recibida",
            pendienteSync = true
        )

        dao.insertOrIgnore(entity)

        if (connectivityObserver.isCurrentlyConnected()) {
            val dto = DenunciaDto(
                clientRequestId = clientRequestId,
                servicioId = entity.servicioId,
                municipioCodigo = municipio,
                lat = lat,
                lng = lng,
                descripcion = descripcion,
                seguimientoHash = seguimientoHash
            )
            val resultado = SupabaseClient.registrarDenuncia(dto)
            if (resultado.isSuccess) {
                dao.marcarSincronizado(id)
                dao.updateEstado(id, "recibida")
            } else {
                OutboxSyncWorker.enqueue(context)
            }
        } else {
            OutboxSyncWorker.enqueue(context)
        }

        // Devuelve el código plano para que el usuario lo guarde
        return Result.success(codigoSeguimiento)
    }

    override suspend fun consultarEstado(codigoSeguimiento: String): Result<Denuncia> {
        val hash = sha256(codigoSeguimiento)

        val local = dao.getByHash(hash)
        if (local != null) {
            return Result.success(local.toDomain())
        }

        if (!connectivityObserver.isCurrentlyConnected()) {
            return Result.failure(Exception("Sin conexión y sin datos locales para este código"))
        }

        return SupabaseClient.consultarDenunciaPorHash(hash).map { dto ->
            Denuncia(
                id = "",
                clientRequestId = dto.clientRequestId,
                servicio = TipoServicio.entries.getOrNull(dto.servicioId - 1) ?: TipoServicio.ENERGIA,
                municipioCodigo = dto.municipioCodigo,
                lat = dto.lat,
                lng = dto.lng,
                descripcion = dto.descripcion,
                codigoSeguimiento = codigoSeguimiento,
                seguimientoHash = hash,
                estado = "recibida",
                pendienteSync = false,
                creadoEn = System.currentTimeMillis(),
                intentos = 0
            )
        }
    }

    private suspend fun sha256(input: String): String = withContext(Dispatchers.Default) {
        val digest = MessageDigest.getInstance("SHA-256")
        val hashBytes = digest.digest(input.toByteArray(Charsets.UTF_8))
        hashBytes.joinToString("") { "%02x".format(it) }
    }

    private fun DenunciaEntity.toDomain() = Denuncia(
        id = id,
        clientRequestId = clientRequestId,
        servicio = TipoServicio.entries.getOrNull(servicioId - 1) ?: TipoServicio.ENERGIA,
        municipioCodigo = municipioCodigo,
        lat = lat,
        lng = lng,
        descripcion = descripcion,
        codigoSeguimiento = codigoSeguimiento,
        seguimientoHash = seguimientoHash,
        estado = estado,
        pendienteSync = pendienteSync,
        creadoEn = creadoEn,
        intentos = intentos
    )
}
