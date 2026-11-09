package com.servired.app.feature.seguimiento

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.SuggestionChipDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SeguimientoScreen(viewModel: SeguimientoViewModel, reporteIdInicial: String? = null) {
    val uiState by viewModel.uiState.collectAsState()
    val isConnected by viewModel.isConnected.collectAsState()

    var modoReporte by remember { mutableStateOf(true) }
    var codigo by remember { mutableStateOf(reporteIdInicial ?: "") }

    Scaffold(
        topBar = {
            TopAppBar(title = { Text("Consultar estado") })
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .padding(horizontal = 16.dp)
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
                        text = "Sin conexión — Solo se muestran datos guardados localmente",
                        modifier = Modifier.padding(12.dp),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(
                    selected = modoReporte,
                    onClick = {
                        modoReporte = true
                        codigo = ""
                        viewModel.limpiarEstado()
                    },
                    label = { Text("Reporte") }
                )
                FilterChip(
                    selected = !modoReporte,
                    onClick = {
                        modoReporte = false
                        codigo = ""
                        viewModel.limpiarEstado()
                    },
                    label = { Text("Denuncia") }
                )
            }

            Spacer(modifier = Modifier.height(12.dp))

            OutlinedTextField(
                value = codigo,
                onValueChange = { codigo = it },
                label = {
                    Text(if (modoReporte) "ID del reporte" else "Código de seguimiento")
                },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            Spacer(modifier = Modifier.height(12.dp))

            Button(
                onClick = {
                    if (modoReporte) viewModel.consultarReporte(codigo)
                    else viewModel.consultarDenuncia(codigo)
                },
                enabled = codigo.isNotBlank() && uiState !is SeguimientoUiState.Loading,
                modifier = Modifier.fillMaxWidth()
            ) {
                if (uiState is SeguimientoUiState.Loading) {
                    CircularProgressIndicator(
                        modifier = Modifier.padding(end = 8.dp),
                        color = MaterialTheme.colorScheme.onPrimary
                    )
                }
                Text("Consultar")
            }

            Spacer(modifier = Modifier.height(16.dp))

            when (val state = uiState) {
                is SeguimientoUiState.Error -> {
                    Text(
                        text = state.msg,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
                is SeguimientoUiState.ReporteEncontrado -> {
                    LineaDeTiempoList(entradas = state.lineasTiempo)
                }
                is SeguimientoUiState.DenunciaEncontrada -> {
                    LineaDeTiempoList(entradas = state.lineasTiempo)
                }
                else -> {}
            }
        }
    }
}

@Composable
private fun LineaDeTiempoList(entradas: List<EntradaLineasTiempo>) {
    LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        items(entradas) { entrada ->
            LineaDeTiempoItem(entrada)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LineaDeTiempoItem(entrada: EntradaLineasTiempo) {
    val formatter = remember { SimpleDateFormat("dd/MM/yyyy HH:mm", Locale.getDefault()) }
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.Top
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = formatter.format(Date(entrada.timestamp)),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = entrada.descripcion,
                style = MaterialTheme.typography.bodyMedium
            )
        }
        SuggestionChip(
            onClick = {},
            label = { Text(entrada.estado) },
            colors = SuggestionChipDefaults.suggestionChipColors(
                containerColor = colorParaEstado(entrada.estado)
            )
        )
    }
}

private fun colorParaEstado(estado: String): Color = when (estado) {
    "recibido", "recibida" -> Color(0xFFE3F2FD)
    "vinculado", "en_revision", "en_atencion" -> Color(0xFFFFF9C4)
    "validada", "restablecido" -> Color(0xFFE8F5E9)
    "descartado", "descartada", "cerrado", "sync_fallido" -> Color(0xFFFFEBEE)
    else -> Color(0xFFF5F5F5)
}
