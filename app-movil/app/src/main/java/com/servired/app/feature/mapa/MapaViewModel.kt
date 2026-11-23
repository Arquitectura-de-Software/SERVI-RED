package com.servired.app.feature.mapa

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.servired.app.core.domain.model.Reporte
import com.servired.app.core.domain.model.TipoServicio
import com.servired.app.core.domain.repository.ReporteRepository
import com.servired.app.core.location.LocationHelper
import com.servired.app.core.network.ConnectivityObserver
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class MapaUiState(
    val cargando: Boolean = false,
    val userLocation: Pair<Double, Double>? = null, // lat, lng
    val reportesLocales: List<Reporte> = emptyList(),
    val elementosVisibles: List<ElementoMapa> = emptyList(),
    val elementoSeleccionado: ElementoMapa? = null,
    val servicioFiltro: TipoServicio? = null,
    val soloIncidentes: Boolean = false,
    val radioBusquedaKm: Double = 25.0,
    val gpsDisponible: Boolean = false,
    val mensajeError: String? = null
)

class MapaViewModel(
    private val reporteRepo: ReporteRepository,
    private val connectivityObserver: ConnectivityObserver,
    private val locationHelper: LocationHelper
) : ViewModel() {

    private val _uiState = MutableStateFlow(MapaUiState())
    val uiState: StateFlow<MapaUiState> = _uiState.asStateFlow()

    private var todosLosElementos: List<ElementoMapa> = emptyList()

    init {
        observarReportesLocales()
        verificarGps()
        actualizarUbicacion(centrarEnGps = true)
    }

    fun verificarGps() {
        val tienePermiso = locationHelper.hasLocationPermission()
        val gpsActivo = locationHelper.isLocationEnabled()
        _uiState.update { it.copy(gpsDisponible = tienePermiso && gpsActivo) }
    }

    private fun observarReportesLocales() {
        viewModelScope.launch {
            reporteRepo.observarTodos().collect { reportes ->
                _uiState.update { it.copy(reportesLocales = reportes) }
                recalcularElementos()
            }
        }
    }

    fun actualizarUbicacion(centrarEnGps: Boolean = false) {
        viewModelScope.launch {
            verificarGps()
            if (!locationHelper.hasLocationPermission()) return@launch

            _uiState.update { it.copy(cargando = true) }
            val location = locationHelper.getCurrentLocation()
            if (location != null) {
                _uiState.update {
                    it.copy(
                        userLocation = Pair(location.latitude, location.longitude),
                        gpsDisponible = true
                    )
                }
                cargarIncidentesRemotos(location.latitude, location.longitude)
            } else {
                _uiState.update { it.copy(cargando = false) }
            }
        }
    }

    fun cargarIncidentesRemotos(lat: Double, lng: Double) {
        viewModelScope.launch {
            _uiState.update { it.copy(cargando = true) }
            val incidentesRemotos = reporteRepo.consultarIncidentesCercanos(
                lat = lat,
                lng = lng,
                radioMetros = _uiState.value.radioBusquedaKm * 1000.0
            )

            val elementosRemotos = incidentesRemotos.map { it.toElementoMapa(lat, lng) }

            // Combinar con reportes locales
            val elementosLocales = _uiState.value.reportesLocales.map { it.toElementoMapa(lat, lng) }

            // Deduplicar por id
            val mapaMap = (elementosRemotos + elementosLocales).associateBy { it.id }
            todosLosElementos = mapaMap.values.toList()

            recalcularElementos()
            _uiState.update { it.copy(cargando = false) }
        }
    }

    private fun recalcularElementos() {
        val userLoc = _uiState.value.userLocation
        val userLat = userLoc?.first
        val userLng = userLoc?.second

        // Si no hay remotos cargados aún, usar al menos los locales
        if (todosLosElementos.isEmpty()) {
            todosLosElementos = _uiState.value.reportesLocales.map { it.toElementoMapa(userLat, userLng) }
        }

        var filtrados = todosLosElementos

        // Filtro por servicio
        _uiState.value.servicioFiltro?.let { s ->
            filtrados = filtrados.filter { it.servicio == s }
        }

        // Filtro solo incidentes de red
        if (_uiState.value.soloIncidentes) {
            filtrados = filtrados.filter { it.esIncidente }
        }

        // Ordenar por cercanía si tenemos ubicación
        if (userLat != null && userLng != null) {
            filtrados = filtrados.sortedBy { it.distanciaMetros ?: Float.MAX_VALUE }
        }

        _uiState.update {
            it.copy(
                elementosVisibles = filtrados,
                elementoSeleccionado = if (it.elementoSeleccionado != null && filtrados.any { f -> f.id == it.elementoSeleccionado.id })
                    it.elementoSeleccionado else null
            )
        }
    }

    fun filtrarPorServicio(servicio: TipoServicio?) {
        _uiState.update { it.copy(servicioFiltro = servicio) }
        recalcularElementos()
    }

    fun alternarSoloIncidentes() {
        _uiState.update { it.copy(soloIncidentes = !it.soloIncidentes) }
        recalcularElementos()
    }

    fun seleccionarElemento(elemento: ElementoMapa?) {
        _uiState.update { it.copy(elementoSeleccionado = elemento) }
    }

    fun limpiarError() {
        _uiState.update { it.copy(mensajeError = null) }
    }
}
