package com.servired.app.navigation

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.servired.app.core.data.local.db.AppDatabase
import com.servired.app.core.network.ConnectivityObserver
import com.servired.app.data.repository.DenunciaRepositoryImpl
import com.servired.app.core.location.LocationHelper
import com.servired.app.data.repository.ReporteRepositoryImpl
import com.servired.app.feature.denuncia.DenunciaScreen
import com.servired.app.feature.denuncia.DenunciaViewModel
import com.servired.app.feature.home.HomeScreen
import com.servired.app.feature.mapa.MapaScreen
import com.servired.app.feature.mapa.MapaViewModel
import com.servired.app.feature.reporte.ReporteScreen
import com.servired.app.feature.reporte.ReporteViewModel
import com.servired.app.feature.seguimiento.SeguimientoScreen
import com.servired.app.feature.seguimiento.SeguimientoViewModel

object Routes {
    const val HOME = "home"
    const val REPORTE_NUEVO = "reporte/nuevo"
    const val SEGUIMIENTO = "seguimiento?reporteId={reporteId}"
    const val SEGUIMIENTO_BASE = "seguimiento"
    const val DENUNCIA_NUEVA = "denuncia/nueva"
    const val MAPA = "mapa"
}

@Composable
fun NavGraph(context: Context, connectivityObserver: ConnectivityObserver) {
    val navController = rememberNavController()

    val db = remember { AppDatabase.getInstance(context) }
    val locationHelper = remember { LocationHelper(context) }
    val reporteRepo = remember { ReporteRepositoryImpl(context, db, connectivityObserver) }
    val denunciaRepo = remember { DenunciaRepositoryImpl(context, db, connectivityObserver) }
    val viewModelFactory = remember { AppViewModelFactory(reporteRepo, denunciaRepo, connectivityObserver, locationHelper) }

    NavHost(navController = navController, startDestination = Routes.HOME) {
        composable(Routes.HOME) {
            HomeScreen(
                connectivityObserver = connectivityObserver,
                onNavigarAReporte = { navController.navigate(Routes.REPORTE_NUEVO) },
                onNavigarASeguimiento = { navController.navigate(Routes.SEGUIMIENTO_BASE) },
                onNavigarADenuncia = { navController.navigate(Routes.DENUNCIA_NUEVA) },
                onNavigarAMapa = { navController.navigate(Routes.MAPA) }
            )
        }

        composable(Routes.MAPA) {
            val viewModel: MapaViewModel = viewModel(factory = viewModelFactory)
            MapaScreen(
                viewModel = viewModel,
                onVolver = { navController.popBackStack() },
                onNavigarASeguimiento = { id -> navController.navigate("seguimiento?reporteId=$id") },
                onNavigarAReporte = { navController.navigate(Routes.REPORTE_NUEVO) }
            )
        }

        composable(Routes.REPORTE_NUEVO) {
            // El ViewModel se conserva a través de recomposiciones y cambios de configuración
            val viewModel: ReporteViewModel = viewModel(factory = viewModelFactory)
            ReporteScreen(
                viewModel = viewModel,
                onNavigarAMapa = { navController.navigate(Routes.MAPA) }
            )
        }

        composable(
            route = Routes.SEGUIMIENTO,
            arguments = listOf(
                navArgument("reporteId") {
                    type = NavType.StringType
                    nullable = true
                    defaultValue = null
                }
            )
        ) { backStack ->
            val reporteId = backStack.arguments?.getString("reporteId")
            val viewModel: SeguimientoViewModel = viewModel(factory = viewModelFactory)
            SeguimientoScreen(viewModel = viewModel, reporteIdInicial = reporteId)
        }

        composable(Routes.DENUNCIA_NUEVA) {
            val viewModel: DenunciaViewModel = viewModel(factory = viewModelFactory)
            DenunciaScreen(viewModel = viewModel)
        }
    }
}
