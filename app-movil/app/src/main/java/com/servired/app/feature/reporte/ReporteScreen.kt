package com.servired.app.feature.reporte

import android.Manifest
import android.app.TimePickerDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.border
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.servired.app.core.domain.model.TipoServicio
import com.servired.app.core.location.LocationHelper
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.time.Instant
import java.util.Calendar
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReporteScreen(viewModel: ReporteViewModel) {
    val uiState by viewModel.uiState.collectAsState()
    val isConnected by viewModel.isConnected.collectAsState()
    val reporteIdCreado by viewModel.reporteIdCreado.collectAsState()
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()

    // Campos del formulario
    var servicioSeleccionado by remember { mutableStateOf(TipoServicio.ENERGIA) }
    var municipio by remember { mutableStateOf("") }
    var lat by remember { mutableStateOf("") }
    var lng by remember { mutableStateOf("") }
    var descripcion by remember { mutableStateOf("") }
    var dropdownExpanded by remember { mutableStateOf(false) }

    // Área afectada
    val opcionesArea = listOf("Mi vivienda", "Cuadra / Manzana", "Sector amplio")
    var areaSeleccionada by remember { mutableStateOf(opcionesArea[0]) }

    // Inicio estimado del corte
    var inicioEstimadoTimestamp by remember { mutableStateOf(System.currentTimeMillis()) }
    var esHoraPersonalizada by remember { mutableStateOf(false) }

    // Evidencia fotográfica
    var selectedImageUri by remember { mutableStateOf<Uri?>(null) }
    var subiendoFoto by remember { mutableStateOf(false) }

    // Estado para geolocalización automática
    val locationHelper = remember { LocationHelper(context) }
    var obteniendoUbicacion by remember { mutableStateOf(false) }
    var mensajeUbicacion by remember { mutableStateOf<String?>(null) }
    var precisionUbicacion by remember { mutableStateOf<Float?>(null) }

    // Formateador de hora para inicio estimado
    val timeFormatter = remember { SimpleDateFormat("hh:mm a", Locale.getDefault()) }

    fun capturarUbicacionGps() {
        if (!locationHelper.isLocationEnabled()) {
            mensajeUbicacion = "El GPS está desactivado en el dispositivo. Actívalo para obtener ubicación."
            return
        }
        obteniendoUbicacion = true
        mensajeUbicacion = null
        coroutineScope.launch {
            val loc = locationHelper.getCurrentLocation()
            obteniendoUbicacion = false
            if (loc != null) {
                lat = String.format(Locale.US, "%.6f", loc.latitude)
                lng = String.format(Locale.US, "%.6f", loc.longitude)
                precisionUbicacion = loc.accuracy
                mensajeUbicacion = "GPS capturado con precisión: ±${loc.accuracy.toInt()} m"
            } else {
                mensajeUbicacion = "No se pudo obtener señal GPS. Puedes ingresar las coordenadas manualmente."
            }
        }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val fineConcedido = permissions[Manifest.permission.ACCESS_FINE_LOCATION] == true
        val coarseConcedido = permissions[Manifest.permission.ACCESS_COARSE_LOCATION] == true
        if (fineConcedido || coarseConcedido) {
            capturarUbicacionGps()
        } else {
            mensajeUbicacion = "Permiso de ubicación denegado. Ingresa las coordenadas manualmente."
        }
    }

    fun solicitarUbicacion() {
        if (locationHelper.hasLocationPermission()) {
            capturarUbicacionGps()
        } else {
            permissionLauncher.launch(
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                )
            )
        }
    }

    val photoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickVisualMedia()
    ) { uri ->
        selectedImageUri = uri
    }

    // Captura automática de GPS si ya se concedieron los permisos previamente
    LaunchedEffect(Unit) {
        if (locationHelper.hasLocationPermission() && lat.isBlank() && lng.isBlank()) {
            capturarUbicacionGps()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(title = { Text("Reportar problema de servicio") })
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .padding(horizontal = 16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.Top
        ) {
            AnimatedVisibility(
                visible = !isConnected,
                enter = expandVertically(),
                exit = shrinkVertically()
            ) {
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    color = MaterialTheme.colorScheme.errorContainer,
                    shape = MaterialTheme.shapes.small
                ) {
                    Text(
                        text = "Sin conexión — El reporte se guardará localmente y se sincronizará al reconectar",
                        modifier = Modifier.padding(12.dp),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // 1. Tipo de servicio
            ExposedDropdownMenuBox(
                expanded = dropdownExpanded,
                onExpandedChange = { dropdownExpanded = it }
            ) {
                OutlinedTextField(
                    value = servicioSeleccionado.name,
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Tipo de servicio afectado") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = dropdownExpanded) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .menuAnchor()
                )
                ExposedDropdownMenu(
                    expanded = dropdownExpanded,
                    onDismissRequest = { dropdownExpanded = false }
                ) {
                    TipoServicio.entries.forEach { tipo ->
                        DropdownMenuItem(
                            text = { Text(tipo.name) },
                            onClick = {
                                servicioSeleccionado = tipo
                                dropdownExpanded = false
                            }
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // 2. Municipio DANE
            OutlinedTextField(
                value = municipio,
                onValueChange = { municipio = it },
                label = { Text("Municipio (código DANE, ej. 11001)") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.fillMaxWidth()
            )

            Spacer(modifier = Modifier.height(16.dp))

            // 3. Geolocalización (GPS Automático)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Coordenadas del incidente",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )

                OutlinedButton(
                    onClick = { solicitarUbicacion() },
                    enabled = !obteniendoUbicacion
                ) {
                    if (obteniendoUbicacion) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            strokeWidth = 2.dp
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text("Detectando...", style = MaterialTheme.typography.labelMedium)
                    } else {
                        Text(
                            if (lat.isNotBlank() && lng.isNotBlank()) "Actualizar GPS" else "Detectar GPS",
                            style = MaterialTheme.typography.labelMedium
                        )
                    }
                }
            }

            mensajeUbicacion?.let { msg ->
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = msg,
                    style = MaterialTheme.typography.bodySmall,
                    color = if (precisionUbicacion != null) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = lat,
                    onValueChange = { lat = it },
                    label = { Text("Latitud") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.weight(1f),
                    supportingText = { if (lat.isNotBlank()) Text("GPS / Editable") }
                )
                OutlinedTextField(
                    value = lng,
                    onValueChange = { lng = it },
                    label = { Text("Longitud") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.weight(1f),
                    supportingText = { if (lng.isNotBlank()) Text("GPS / Editable") }
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            // 4. Área afectada
            Text(
                text = "Alcance estimado del corte",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(modifier = Modifier.height(6.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                opcionesArea.forEach { opcion ->
                    FilterChip(
                        selected = areaSeleccionada == opcion,
                        onClick = { areaSeleccionada = opcion },
                        label = { Text(opcion) }
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // 5. Inicio estimado del corte
            Text(
                text = "Inicio estimado de la interrupción",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(modifier = Modifier.height(6.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = if (esHoraPersonalizada) {
                        "Inicio: ${timeFormatter.format(Date(inicioEstimadoTimestamp))}"
                    } else {
                        "Inicio: Hace un momento (Ahora)"
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                OutlinedButton(
                    onClick = {
                        val cal = Calendar.getInstance().apply { timeInMillis = inicioEstimadoTimestamp }
                        TimePickerDialog(
                            context,
                            { _, hourOfDay, minute ->
                                val nuevoCal = Calendar.getInstance().apply {
                                    set(Calendar.HOUR_OF_DAY, hourOfDay)
                                    set(Calendar.MINUTE, minute)
                                    set(Calendar.SECOND, 0)
                                }
                                inicioEstimadoTimestamp = nuevoCal.timeInMillis
                                esHoraPersonalizada = true
                            },
                            cal.get(Calendar.HOUR_OF_DAY),
                            cal.get(Calendar.MINUTE),
                            false
                        ).show()
                    }
                ) {
                    Text(if (esHoraPersonalizada) "Cambiar hora" else "Ajustar hora")
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // 6. Evidencia fotográfica
            Text(
                text = "Foto de evidencia (Opcional)",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(modifier = Modifier.height(6.dp))

            if (selectedImageUri == null) {
                OutlinedButton(
                    onClick = {
                        photoPickerLauncher.launch(
                            PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
                        )
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Seleccionar o tomar fotografía")
                }
            } else {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(8.dp))
                        .padding(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    AsyncImage(
                        model = selectedImageUri,
                        contentDescription = "Foto de evidencia adjunta",
                        modifier = Modifier
                            .size(72.dp)
                            .clip(RoundedCornerShape(8.dp)),
                        contentScale = ContentScale.Crop
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Text(
                        text = "Foto adjuntada",
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.weight(1f)
                    )
                    TextButton(onClick = { selectedImageUri = null }) {
                        Text("Quitar", color = MaterialTheme.colorScheme.error)
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // 7. Descripción
            OutlinedTextField(
                value = descripcion,
                onValueChange = { if (it.length <= 1000) descripcion = it },
                label = { Text("Descripción del problema (opcional)") },
                modifier = Modifier.fillMaxWidth(),
                maxLines = 4,
                supportingText = { Text("${descripcion.length}/1000") }
            )

            Spacer(modifier = Modifier.height(16.dp))

            if (uiState is ReporteUiState.Error) {
                Text(
                    text = (uiState as ReporteUiState.Error).msg,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall
                )
                Spacer(modifier = Modifier.height(8.dp))
            }

            // 8. Botón Enviar
            Button(
                onClick = {
                    val latDouble = lat.toDoubleOrNull() ?: return@Button
                    val lngDouble = lng.toDoubleOrNull() ?: return@Button

                    val inicioIso = Instant.ofEpochMilli(inicioEstimadoTimestamp).toString()
                    val descFinal = buildString {
                        append("[Área: $areaSeleccionada] ")
                        if (descripcion.isNotBlank()) append(descripcion.trim())
                    }

                    if (selectedImageUri != null) {
                        subiendoFoto = true
                        coroutineScope.launch {
                            val bytes = context.contentResolver.openInputStream(selectedImageUri!!)?.use {
                                it.readBytes()
                            }
                            if (bytes != null) {
                                viewModel.subirEvidencia(bytes) { res ->
                                    subiendoFoto = false
                                    val pathEvidencia = res.getOrNull()
                                    viewModel.crearReporte(
                                        servicio = servicioSeleccionado,
                                        municipio = municipio,
                                        lat = latDouble,
                                        lng = lngDouble,
                                        descripcion = descFinal,
                                        urlEvidencia = pathEvidencia,
                                        inicioEstimado = inicioIso
                                    )
                                }
                            } else {
                                subiendoFoto = false
                                viewModel.crearReporte(
                                    servicio = servicioSeleccionado,
                                    municipio = municipio,
                                    lat = latDouble,
                                    lng = lngDouble,
                                    descripcion = descFinal,
                                    urlEvidencia = null,
                                    inicioEstimado = inicioIso
                                )
                            }
                        }
                    } else {
                        viewModel.crearReporte(
                            servicio = servicioSeleccionado,
                            municipio = municipio,
                            lat = latDouble,
                            lng = lngDouble,
                            descripcion = descFinal,
                            urlEvidencia = null,
                            inicioEstimado = inicioIso
                        )
                    }
                },
                enabled = uiState !is ReporteUiState.Loading && !subiendoFoto
                        && municipio.isNotBlank() && lat.isNotBlank() && lng.isNotBlank(),
                modifier = Modifier.fillMaxWidth()
            ) {
                if (uiState is ReporteUiState.Loading || subiendoFoto) {
                    CircularProgressIndicator(
                        modifier = Modifier
                            .size(20.dp)
                            .padding(end = 8.dp),
                        color = MaterialTheme.colorScheme.onPrimary,
                        strokeWidth = 2.dp
                    )
                }
                Text(if (subiendoFoto) "Subiendo foto..." else "Enviar reporte")
            }

            // Confirmación con ID de trazabilidad
            reporteIdCreado?.let { idCreado ->
                Spacer(modifier = Modifier.height(16.dp))
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.primaryContainer
                    )
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            text = "Reporte recibido con éxito",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            text = "Tu incidencia ha sido registrada en el sistema. Puedes hacer seguimiento con este identificador.",
                            style = MaterialTheme.typography.bodySmall
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = "ID de Trazabilidad: $idCreado",
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        Spacer(modifier = Modifier.height(12.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedButton(
                                onClick = {
                                    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                    clipboard.setPrimaryClip(ClipData.newPlainText("ID Reporte", idCreado))
                                },
                                modifier = Modifier.weight(1f)
                            ) {
                                Text("Copiar ID")
                            }
                            Button(
                                onClick = {
                                    viewModel.limpiarReporteIdCreado()
                                    lat = ""
                                    lng = ""
                                    descripcion = ""
                                    selectedImageUri = null
                                    mensajeUbicacion = null
                                },
                                modifier = Modifier.weight(1f)
                            ) {
                                Text("Nuevo reporte")
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(24.dp))
        }
    }
}
