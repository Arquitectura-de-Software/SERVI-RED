package com.servired.app.feature.seguimiento

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.servired.app.core.domain.model.Denuncia
import com.servired.app.core.domain.model.Reporte
import com.servired.app.core.domain.repository.DenunciaRepository
import com.servired.app.core.domain.repository.ReporteRepository
import com.servired.app.core.network.ConnectivityObserver
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

data class EntradaLineasTiempo(
    val timestamp: Long,
    val estado: String,
    val descripcion: String
)

sealed class SeguimientoUiState {
    object Idle : SeguimientoUiState()
    object Loading : SeguimientoUiState()
    data class ReporteEncontrado(
        val reporte: Reporte,
        val lineasTiempo: List<EntradaLineasTiempo>
    ) : SeguimientoUiState()
    data class DenunciaEncontrada(
        val denuncia: Denuncia,
        val lineasTiempo: List<EntradaLineasTiempo>
    ) : SeguimientoUiState()
    data class Error(val msg: String) : SeguimientoUiState()
}

class SeguimientoViewModel(
    private val reporteRepository: ReporteRepository,
    private val denunciaRepository: DenunciaRepository,
    private val connectivityObserver: ConnectivityObserver
) : ViewModel() {

    private val _uiState = MutableStateFlow<SeguimientoUiState>(SeguimientoUiState.Idle)
    val uiState: StateFlow<SeguimientoUiState> = _uiState.asStateFlow()

    private val _isConnected = MutableStateFlow(true)
    val isConnected: StateFlow<Boolean> = _isConnected.asStateFlow()

    init {
        viewModelScope.launch {
            connectivityObserver.isConnected.collectLatest { connected ->
                _isConnected.value = connected
            }
        }
    }

    fun consultarReporte(id: String) {
        viewModelScope.launch {
            _uiState.value = SeguimientoUiState.Loading
            val resultado = reporteRepository.consultarPorId(id)
            if (resultado.isSuccess) {
                val reporte = resultado.getOrNull()!!
                _uiState.value = SeguimientoUiState.ReporteEncontrado(
                    reporte = reporte,
                    lineasTiempo = construirLineasTiempoReporte(reporte)
                )
            } else {
                _uiState.value = SeguimientoUiState.Error(
                    resultado.exceptionOrNull()?.message ?: "No se encontró el reporte"
                )
            }
        }
    }

    fun consultarDenuncia(codigoSeguimiento: String) {
        viewModelScope.launch {
            _uiState.value = SeguimientoUiState.Loading
            val resultado = denunciaRepository.consultarEstado(codigoSeguimiento)
            if (resultado.isSuccess) {
                val denuncia = resultado.getOrNull()!!
                _uiState.value = SeguimientoUiState.DenunciaEncontrada(
                    denuncia = denuncia,
                    lineasTiempo = construirLineasTiempoDenuncia(denuncia)
                )
            } else {
                _uiState.value = SeguimientoUiState.Error(
                    resultado.exceptionOrNull()?.message ?: "No se encontró la denuncia"
                )
            }
        }
    }

    private fun construirLineasTiempoReporte(reporte: Reporte): List<EntradaLineasTiempo> {
        val entradas = mutableListOf<EntradaLineasTiempo>()
        entradas.add(
            EntradaLineasTiempo(
                timestamp = reporte.creadoEn,
                estado = "recibido",
                descripcion = "Reporte registrado en el sistema"
            )
        )
        when (reporte.estado) {
            "vinculado" -> entradas.add(
                EntradaLineasTiempo(
                    timestamp = System.currentTimeMillis(),
                    estado = "vinculado",
                    descripcion = "El reporte fue vinculado a un incidente activo"
                )
            )
            "descartado" -> entradas.add(
                EntradaLineasTiempo(
                    timestamp = System.currentTimeMillis(),
                    estado = "descartado",
                    descripcion = "El reporte fue descartado por no cumplir criterios"
                )
            )
            "sync_fallido" -> entradas.add(
                EntradaLineasTiempo(
                    timestamp = System.currentTimeMillis(),
                    estado = "sync_fallido",
                    descripcion = "No se pudo sincronizar tras múltiples intentos"
                )
            )
        }
        return entradas
    }

    private fun construirLineasTiempoDenuncia(denuncia: Denuncia): List<EntradaLineasTiempo> {
        val entradas = mutableListOf<EntradaLineasTiempo>()
        entradas.add(
            EntradaLineasTiempo(
                timestamp = denuncia.creadoEn,
                estado = "recibida",
                descripcion = "Denuncia registrada de forma anónima"
            )
        )
        when (denuncia.estado) {
            "en_revision" -> entradas.add(
                EntradaLineasTiempo(
                    timestamp = System.currentTimeMillis(),
                    estado = "en_revision",
                    descripcion = "La denuncia está siendo revisada por el equipo"
                )
            )
            "validada" -> entradas.add(
                EntradaLineasTiempo(
                    timestamp = System.currentTimeMillis(),
                    estado = "validada",
                    descripcion = "La denuncia fue validada y está siendo procesada"
                )
            )
            "descartada" -> entradas.add(
                EntradaLineasTiempo(
                    timestamp = System.currentTimeMillis(),
                    estado = "descartada",
                    descripcion = "La denuncia fue descartada"
                )
            )
        }
        return entradas
    }

    fun limpiarEstado() {
        _uiState.value = SeguimientoUiState.Idle
    }
}
