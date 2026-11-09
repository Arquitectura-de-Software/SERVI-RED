package com.servired.app.core.data.sync

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.servired.app.core.data.local.db.AppDatabase
import com.servired.app.core.data.remote.SupabaseClient
import com.servired.app.core.data.remote.dto.DenunciaDto
import com.servired.app.core.data.remote.dto.ReporteDto
import java.util.concurrent.TimeUnit

// WorkManager requiere: implementation("androidx.work:work-runtime-ktx:2.9.0")
class OutboxSyncWorker(
    private val context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    private val db = AppDatabase.getInstance(context)
    private val reporteDao = db.reporteDao()
    private val denunciaDao = db.denunciaDao()

    override suspend fun doWork(): Result {
        var todosExitosos = true

        val reportesPendientes = reporteDao.getPendientes()
        for (reporte in reportesPendientes) {
            if (reporte.intentosSincronizacion >= 5) continue

            val dto = ReporteDto(
                clientRequestId = reporte.clientRequestId,
                servicioId = reporte.servicioId,
                municipioCodigo = reporte.municipioCodigo,
                lat = reporte.lat,
                lng = reporte.lng,
                descripcion = reporte.descripcion
            )

            val resultado = SupabaseClient.registrarReporte(dto)
            if (resultado.isSuccess) {
                reporteDao.marcarSincronizado(reporte.id)
                val remoteEstado = resultado.getOrNull()?.estado ?: "recibido"
                reporteDao.updateEstado(reporte.id, remoteEstado)
            } else {
                reporteDao.incrementarIntentos(reporte.id)
                if (reporte.intentosSincronizacion + 1 >= 5) {
                    reporteDao.updateEstado(reporte.id, "sync_fallido")
                }
                todosExitosos = false
            }
        }

        val denunciasPendientes = denunciaDao.getPendientes()
        for (denuncia in denunciasPendientes) {
            if (denuncia.intentos >= 5) continue

            val dto = DenunciaDto(
                clientRequestId = denuncia.clientRequestId,
                servicioId = denuncia.servicioId,
                municipioCodigo = denuncia.municipioCodigo,
                lat = denuncia.lat,
                lng = denuncia.lng,
                descripcion = denuncia.descripcion,
                seguimientoHash = denuncia.seguimientoHash
            )

            val resultado = SupabaseClient.registrarDenuncia(dto)
            if (resultado.isSuccess) {
                denunciaDao.marcarSincronizado(denuncia.id)
                denunciaDao.updateEstado(denuncia.id, "recibida")
            } else {
                denunciaDao.incrementarIntentos(denuncia.id)
                if (denuncia.intentos + 1 >= 5) {
                    denunciaDao.updateEstado(denuncia.id, "sync_fallido")
                }
                todosExitosos = false
            }
        }

        return if (todosExitosos) Result.success() else Result.retry()
    }

    companion object {
        fun enqueue(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val request = OneTimeWorkRequestBuilder<OutboxSyncWorker>()
                .setConstraints(constraints)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 15, TimeUnit.SECONDS)
                .build()

            WorkManager.getInstance(context).enqueue(request)
        }
    }
}
