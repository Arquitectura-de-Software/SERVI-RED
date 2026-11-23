package com.servired.app.feature.mapa

import android.Manifest
import android.content.Context
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Badge
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.servired.app.core.domain.model.TipoServicio
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.CustomZoomButtonsController
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MapaScreen(
    viewModel: MapaViewModel,
    onVolver: () -> Unit,
    onNavigarASeguimiento: (String) -> Unit,
    onNavigarAReporte: () -> Unit
) {
    val uiState by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    // Permisos de ubicación
    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val fineGranted = permissions[Manifest.permission.ACCESS_FINE_LOCATION] ?: false
        val coarseGranted = permissions[Manifest.permission.ACCESS_COARSE_LOCATION] ?: false
        if (fineGranted || coarseGranted) {
            viewModel.actualizarUbicacion(centrarEnGps = true)
        }
    }

    LaunchedEffect(Unit) {
        permissionLauncher.launch(
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            )
        )
    }

    // Instancia recordada de MapView para OSMDroid
    val mapView = remember {
        Configuration.getInstance().userAgentValue = context.packageName
        Configuration.getInstance().load(context, context.getSharedPreferences("osmdroid", Context.MODE_PRIVATE))

        MapView(context).apply {
            setTileSource(TileSourceFactory.MAPNIK)
            setMultiTouchControls(true)
            isTilesScaledToDpi = true
            zoomController.setVisibility(CustomZoomButtonsController.Visibility.NEVER)
            controller.setZoom(15.0)
            controller.setCenter(GeoPoint(4.6097, -74.0817)) // Centro Colombia por defecto
        }
    }

    // Ciclo de vida para pausar hilos de tiles de OSMDroid
    DisposableEffect(lifecycleOwner, mapView) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> mapView.onResume()
                Lifecycle.Event.ON_PAUSE -> mapView.onPause()
                Lifecycle.Event.ON_DESTROY -> mapView.onDetach()
                else -> {}
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            mapView.onDetach()
        }
    }

    // Cuando cambia la ubicación del usuario, animar el mapa hacia sus coordenadas
    LaunchedEffect(uiState.userLocation) {
        uiState.userLocation?.let { (lat, lng) ->
            mapView.controller.animateTo(GeoPoint(lat, lng))
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Mapa de Incidentes", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onVolver) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Volver")
                    }
                },
                actions = {
                    if (uiState.cargando) {
                        CircularProgressIndicator(
                            modifier = Modifier
                                .size(24.dp)
                                .padding(end = 8.dp),
                            strokeWidth = 2.dp
                        )
                    } else {
                        IconButton(onClick = { viewModel.actualizarUbicacion(centrarEnGps = true) }) {
                            Icon(Icons.Default.Refresh, contentDescription = "Actualizar mapa")
                        }
                    }
                }
            )
        }
    ) { paddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            // Mapa OSMDroid renderizado nativamente
            AndroidView(
                modifier = Modifier.fillMaxSize(),
                factory = { mapView },
                update = { map ->
                    map.overlays.clear()

                    // Marcador de la posición del usuario
                    uiState.userLocation?.let { (userLat, userLng) ->
                        val userMarker = Marker(map).apply {
                            position = GeoPoint(userLat, userLng)
                            title = "Mi Ubicación"
                            snippet = "Precisión GPS obtenida"
                            setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
                            icon = MarkerBitmapHelper.crearIconoUsuario(context)
                        }
                        map.overlays.add(userMarker)
                    }

                    // Marcadores de reportes e incidentes
                    for (elemento in uiState.elementosVisibles) {
                        val marker = Marker(map).apply {
                            position = GeoPoint(elemento.lat, elemento.lng)
                            title = elemento.titulo
                            snippet = elemento.descripcion ?: "Sin descripción"
                            setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
                            icon = MarkerBitmapHelper.crearIconoServicio(
                                context,
                                elemento.servicio,
                                elemento.esIncidente
                            )
                            setOnMarkerClickListener { m, _ ->
                                m.showInfoWindow()
                                viewModel.seleccionarElemento(elemento)
                                true
                            }
                        }
                        map.overlays.add(marker)
                    }

                    map.invalidate()
                }
            )

            // Fila superior de filtros por servicio
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .align(Alignment.TopCenter)
                    .padding(8.dp)
            ) {
                FiltrosServicioRow(
                    servicioSeleccionado = uiState.servicioFiltro,
                    soloIncidentes = uiState.soloIncidentes,
                    onSeleccionarServicio = { viewModel.filtrarPorServicio(it) },
                    onAlternarSoloIncidentes = { viewModel.alternarSoloIncidentes() }
                )

                // Indicador de cantidad de reportes visibles
                Surface(
                    shape = MaterialTheme.shapes.extraSmall,
                    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.85f),
                    modifier = Modifier.padding(top = 4.dp, start = 4.dp)
                ) {
                    Text(
                        text = "${uiState.elementosVisibles.size} eventos en la zona",
                        style = MaterialTheme.typography.labelSmall,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                    )
                }
            }

            // Botones de acción flotantes a la derecha
            Column(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(end = 16.dp, bottom = if (uiState.elementoSeleccionado != null) 200.dp else 16.dp),
                horizontalAlignment = Alignment.End,
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                // Botón para centrar en GPS
                FloatingActionButton(
                    onClick = {
                        uiState.userLocation?.let { (lat, lng) ->
                            mapView.controller.animateTo(GeoPoint(lat, lng))
                        } ?: run {
                            viewModel.actualizarUbicacion(centrarEnGps = true)
                        }
                    },
                    containerColor = MaterialTheme.colorScheme.surface,
                    contentColor = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(48.dp)
                ) {
                    Icon(Icons.Default.MyLocation, contentDescription = "Centrar en mi ubicación")
                }

                // Botón para reportar nueva interrupción
                ExtendedFloatingActionButton(
                    text = { Text("Reportar falla") },
                    icon = { Icon(Icons.Default.Add, contentDescription = null) },
                    onClick = onNavigarAReporte
                )
            }

            // Tarjeta inferior con el detalle del elemento seleccionado
            AnimatedVisibility(
                visible = uiState.elementoSeleccionado != null,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .padding(16.dp),
                enter = slideInVertically(initialOffsetY = { it }) + fadeIn(),
                exit = slideOutVertically(targetOffsetY = { it }) + fadeOut()
            ) {
                uiState.elementoSeleccionado?.let { elemento ->
                    TarjetaDetalleElemento(
                        elemento = elemento,
                        onCerrar = { viewModel.seleccionarElemento(null) },
                        onVerSeguimiento = { onNavigarASeguimiento(elemento.id) }
                    )
                }
            }
        }
    }
}

@Composable
private fun FiltrosServicioRow(
    servicioSeleccionado: TipoServicio?,
    soloIncidentes: Boolean,
    onSeleccionarServicio: (TipoServicio?) -> Unit,
    onAlternarSoloIncidentes: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        FilterChip(
            selected = servicioSeleccionado == null,
            onClick = { onSeleccionarServicio(null) },
            label = { Text("Todos") }
        )

        FilterChip(
            selected = soloIncidentes,
            onClick = onAlternarSoloIncidentes,
            label = { Text("⚡ Solo incidentes de red") },
            leadingIcon = if (soloIncidentes) {
                { Icon(Icons.Default.Warning, contentDescription = null, modifier = Modifier.size(16.dp)) }
            } else null
        )

        TipoServicio.entries.forEach { servicio ->
            FilterChip(
                selected = servicioSeleccionado == servicio,
                onClick = {
                    if (servicioSeleccionado == servicio) onSeleccionarServicio(null)
                    else onSeleccionarServicio(servicio)
                },
                label = {
                    Text(
                        when (servicio) {
                            TipoServicio.ACUEDUCTO -> "💧 Agua"
                            TipoServicio.ENERGIA -> "⚡ Energía"
                            TipoServicio.GAS -> "🔥 Gas"
                            TipoServicio.ALCANTARILLADO -> "🚽 Alcantarillado"
                            TipoServicio.ASEO -> "🧹 Aseo"
                        }
                    )
                }
            )
        }
    }
}

@Composable
private fun TarjetaDetalleElemento(
    elemento: ElementoMapa,
    onCerrar: () -> Unit,
    onVerSeguimiento: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 8.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    val colorServicio = when (elemento.servicio) {
                        TipoServicio.ACUEDUCTO -> Color(0xFF0288D1)
                        TipoServicio.ENERGIA -> Color(0xFFF57C00)
                        TipoServicio.GAS -> Color(0xFFD32F2F)
                        TipoServicio.ALCANTARILLADO -> Color(0xFF7B1FA2)
                        TipoServicio.ASEO -> Color(0xFF388E3C)
                    }

                    Surface(
                        shape = MaterialTheme.shapes.small,
                        color = colorServicio.copy(alpha = 0.15f),
                        modifier = Modifier.padding(end = 8.dp)
                    ) {
                        Text(
                            text = elemento.servicio.name,
                            color = colorServicio,
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                        )
                    }

                    Badge(
                        containerColor = when (elemento.estado) {
                            "restablecido", "cerrado" -> Color(0xFF2E7D32)
                            "en_atencion", "vinculado" -> Color(0xFF1976D2)
                            else -> MaterialTheme.colorScheme.secondaryContainer
                        }
                    ) {
                        Text(
                            text = elemento.estado.uppercase(),
                            style = MaterialTheme.typography.labelSmall
                        )
                    }
                }

                IconButton(onClick = onCerrar, modifier = Modifier.size(24.dp)) {
                    Icon(Icons.Default.Close, contentDescription = "Cerrar")
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = elemento.titulo,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )

            if (!elemento.descripcion.isNullOrBlank()) {
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = elemento.descripcion,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            elemento.distanciaMetros?.let { distancia ->
                Spacer(modifier = Modifier.height(6.dp))
                val distanciaTexto = if (distancia >= 1000) {
                    "%.1f km".format(distancia / 1000f)
                } else {
                    "${distancia.toInt()} m"
                }
                Text(
                    text = "📍 A $distanciaTexto de tu ubicación",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.Medium
                )
            }

            Spacer(modifier = Modifier.height(12.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                OutlinedButton(onClick = onVerSeguimiento) {
                    Text("Ver seguimiento")
                }
            }
        }
    }
}
