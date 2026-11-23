package com.servired.app.feature.reporte

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.servired.app.core.data.remote.SupabaseClient
import com.servired.app.core.domain.model.Reporte
import com.servired.app.core.domain.model.ReporteCreado
import com.servired.app.core.domain.model.TipoServicio
import com.servired.app.core.domain.repository.ReporteRepository
import com.servired.app.core.network.ConnectivityObserver
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

sealed class ReporteUiState {
    object Idle : ReporteUiState()
    object Loading : ReporteUiState()
    data class Success(val reportes: List<Reporte>, val reporteIdCreado: String? = null) : ReporteUiState()
    data class Error(val msg: String) : ReporteUiState()
}

class ReporteViewModel(
    private val repository: ReporteRepository,
    private val connectivityObserver: ConnectivityObserver
) : ViewModel() {

    private val _uiState = MutableStateFlow<ReporteUiState>(ReporteUiState.Idle)
    val uiState: StateFlow<ReporteUiState> = _uiState.asStateFlow()

    private val _isConnected = MutableStateFlow(true)
    val isConnected: StateFlow<Boolean> = _isConnected.asStateFlow()

    private val _reporteIdCreado = MutableStateFlow<String?>(null)
    val reporteIdCreado: StateFlow<String?> = _reporteIdCreado.asStateFlow()

    // ── Punto 5: metadatos de duplicado/incidente cercano ────────────────────
    /** Resultado completo del último crearReporte (incluye flags de duplicado). */
    private val _reporteCreado = MutableStateFlow<ReporteCreado?>(null)
    val reporteCreado: StateFlow<ReporteCreado?> = _reporteCreado.asStateFlow()

    init {
        observarConectividad()
        cargarReportes()
    }

    private fun observarConectividad() {
        viewModelScope.launch {
            connectivityObserver.isConnected.collectLatest { connected ->
                _isConnected.value = connected
            }
        }
    }

    private fun cargarReportes() {
        viewModelScope.launch {
            repository.observarTodos().collectLatest { lista ->
                _uiState.value = ReporteUiState.Success(lista)
            }
        }
    }

    fun crearReporte(
        servicio: TipoServicio,
        municipio: String,
        lat: Double,
        lng: Double,
        descripcion: String?,
        urlEvidencia: String? = null,
        inicioEstimado: String? = null
    ) {
        viewModelScope.launch {
            _uiState.value = ReporteUiState.Loading
            val resultado = repository.crearReporte(
                servicio = servicio,
                municipio = municipio,
                lat = lat,
                lng = lng,
                descripcion = descripcion,
                urlEvidencia = urlEvidencia,
                inicioEstimado = inicioEstimado
            )
            if (resultado.isSuccess) {
                val creado = resultado.getOrNull()!!
                _reporteCreado.value = creado
                _reporteIdCreado.value = creado.reporteId
                cargarReportes()
            } else {
                _uiState.value = ReporteUiState.Error(
                    resultado.exceptionOrNull()?.message ?: "Error desconocido"
                )
            }
        }
    }

    fun subirEvidencia(byteArray: ByteArray, onResultado: (Result<String>) -> Unit) {
        viewModelScope.launch {
            val resultado = SupabaseClient.subirEvidenciaReporte(byteArray)
            onResultado(resultado)
        }
    }

    fun consultarReporte(id: String) {
        viewModelScope.launch {
            _uiState.value = ReporteUiState.Loading
            val resultado = repository.consultarPorId(id)
            if (resultado.isSuccess) {
                _uiState.value = ReporteUiState.Success(
                    reportes = listOfNotNull(resultado.getOrNull()),
                    reporteIdCreado = id
                )
            } else {
                _uiState.value = ReporteUiState.Error(
                    resultado.exceptionOrNull()?.message ?: "No se encontró el reporte"
                )
            }
        }
    }

    fun limpiarReporteIdCreado() {
        _reporteIdCreado.value = null
        _reporteCreado.value = null
    }
}

