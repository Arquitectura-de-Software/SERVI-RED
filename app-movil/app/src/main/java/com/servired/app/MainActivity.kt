package com.servired.app

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import com.servired.app.core.network.ConnectivityObserver
import com.servired.app.navigation.NavGraph
import com.servired.app.ui.theme.ServiRedAppTheme

class MainActivity : ComponentActivity() {

    private lateinit var connectivityObserver: ConnectivityObserver

    // Solicita permiso de notificaciones en Android 13+
    private val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { /* El usuario aceptó o rechazó; la app funciona en ambos casos */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        connectivityObserver = ConnectivityObserver(applicationContext)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }

        setContent {
            ServiRedAppTheme {
                NavGraph(
                    context = applicationContext,
                    connectivityObserver = connectivityObserver
                )
            }
        }
    }
}
