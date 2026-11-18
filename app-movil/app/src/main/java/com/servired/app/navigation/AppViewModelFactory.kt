package com.servired.app.navigation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import com.servired.app.core.domain.repository.DenunciaRepository
import com.servired.app.core.domain.repository.ReporteRepository
import com.servired.app.core.network.ConnectivityObserver
import com.servired.app.feature.denuncia.DenunciaViewModel
import com.servired.app.feature.reporte.ReporteViewModel
import com.servired.app.feature.seguimiento.SeguimientoViewModel

class AppViewModelFactory(
    private val reporteRepo: ReporteRepository,
    private val denunciaRepo: DenunciaRepository,
    private val connectivityObserver: ConnectivityObserver
) : ViewModelProvider.Factory {

    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        return when {
            modelClass.isAssignableFrom(ReporteViewModel::class.java) -> {
                ReporteViewModel(reporteRepo, connectivityObserver) as T
            }
            modelClass.isAssignableFrom(SeguimientoViewModel::class.java) -> {
                SeguimientoViewModel(reporteRepo, denunciaRepo, connectivityObserver) as T
            }
            modelClass.isAssignableFrom(DenunciaViewModel::class.java) -> {
                DenunciaViewModel(denunciaRepo, connectivityObserver) as T
            }
            else -> throw IllegalArgumentException("Clase de ViewModel desconocida: ${modelClass.name}")
        }
    }
}
