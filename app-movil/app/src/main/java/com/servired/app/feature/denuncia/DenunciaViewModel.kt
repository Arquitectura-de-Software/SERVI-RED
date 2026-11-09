package com.servired.app.feature.denuncia

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.servired.app.core.domain.model.Denuncia
import com.servired.app.core.domain.model.TipoServicio
import com.servired.app.core.domain.repository.DenunciaRepository
import com.servired.app.core.network.ConnectivityObserver
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

sealed class DenunciaUiState {
    object Idle : DenunciaUiState()
    object Loading : DenunciaUiState()
    data class Enviada(val codigoSeguimiento: String) : DenunciaUiState()
    data class ConsultaExitosa(val denuncia: Denuncia) : DenunciaUiState()
    data class Error(val msg: String) : DenunciaUiState()
}

class DenunciaViewModel(
    private val repository: DenunciaRepository,
    private val connectivityObserver: ConnectivityObserver
) : ViewModel() {

    private val _uiState = MutableStateFlow<DenunciaUiState>(DenunciaUiState.Idle)
    val uiState: StateFlow<DenunciaUiState> = _uiState.asStateFlow()

    private val _isConnected = MutableStateFlow(true)
    val isConnected: StateFlow<Boolean> = _isConnected.asStateFlow()

    // El código se expone solo una vez y se limpia al navegar
    private val _codigoGenerado = MutableStateFlow<String?>(null)
    val codigoGenerado: StateFlow<String?> = _codigoGenerado.asStateFlow()

    init {
        viewModelScope.launch {
            connectivityObserver.isConnected.collectLatest { connected ->
                _isConnected.value = connected
            }
        }
    }

    fun enviarDenuncia(
        servicio: TipoServicio,
        municipio: String,
        descripcion: String,
        lat: Double?,
        lng: Double?
    ) {
        if (descripcion.length < 10 || descripcion.length > 2000) {
            _uiState.value = DenunciaUiState.Error("La descripción debe tener entre 10 y 2000 caracteres")
            return
        }

        viewModelScope.launch {
            _uiState.value = DenunciaUiState.Loading
            val resultado = repository.enviarDenuncia(servicio, municipio, descripcion, lat, lng)
            if (resultado.isSuccess) {
                val codigo = resultado.getOrNull()!!
                _codigoGenerado.value = codigo
                _uiState.value = DenunciaUiState.Enviada(codigo)
            } else {
                _uiState.value = DenunciaUiState.Error(
                    resultado.exceptionOrNull()?.message ?: "Error al enviar denuncia"
                )
            }
        }
    }

    fun consultarEstado(codigoSeguimiento: String) {
        viewModelScope.launch {
            _uiState.value = DenunciaUiState.Loading
            val resultado = repository.consultarEstado(codigoSeguimiento)
            if (resultado.isSuccess) {
                _uiState.value = DenunciaUiState.ConsultaExitosa(resultado.getOrNull()!!)
            } else {
                _uiState.value = DenunciaUiState.Error(
                    resultado.exceptionOrNull()?.message ?: "No se encontró la denuncia"
                )
            }
        }
    }

    fun limpiarEstado() {
        _uiState.value = DenunciaUiState.Idle
        _codigoGenerado.value = null
    }
}
