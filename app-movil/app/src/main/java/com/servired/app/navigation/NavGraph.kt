package com.servired.app.navigation

import androidx.compose.runtime.Composable
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.servired.app.core.data.local.db.AppDatabase
import com.servired.app.core.network.ConnectivityObserver
import com.servired.app.data.repository.DenunciaRepositoryImpl
import com.servired.app.data.repository.ReporteRepositoryImpl
import com.servired.app.feature.denuncia.DenunciaScreen
import com.servired.app.feature.denuncia.DenunciaViewModel
import com.servired.app.feature.home.HomeScreen
import com.servired.app.feature.reporte.ReporteScreen
import com.servired.app.feature.reporte.ReporteViewModel
import com.servired.app.feature.seguimiento.SeguimientoScreen
import com.servired.app.feature.seguimiento.SeguimientoViewModel
import android.content.Context

object Routes {
    const val HOME = "home"
    const val REPORTE_NUEVO = "reporte/nuevo"
    const val SEGUIMIENTO = "seguimiento?reporteId={reporteId}"
    const val SEGUIMIENTO_BASE = "seguimiento"
    const val DENUNCIA_NUEVA = "denuncia/nueva"
}

@Composable
fun NavGraph(context: Context, connectivityObserver: ConnectivityObserver) {
    val navController = rememberNavController()
    val db = AppDatabase.getInstance(context)

    val reporteRepo = ReporteRepositoryImpl(context, db, connectivityObserver)
    val denunciaRepo = DenunciaRepositoryImpl(context, db, connectivityObserver)

    NavHost(navController = navController, startDestination = Routes.HOME) {
        composable(Routes.HOME) {
            HomeScreen(
                connectivityObserver = connectivityObserver,
                onNavigarAReporte = { navController.navigate(Routes.REPORTE_NUEVO) },
                onNavigarASeguimiento = { navController.navigate(Routes.SEGUIMIENTO_BASE) },
                onNavigarADenuncia = { navController.navigate(Routes.DENUNCIA_NUEVA) }
            )
        }

        composable(Routes.REPORTE_NUEVO) {
            val viewModel = ReporteViewModel(reporteRepo, connectivityObserver)
            ReporteScreen(viewModel = viewModel)
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
            val viewModel = SeguimientoViewModel(reporteRepo, denunciaRepo, connectivityObserver)
            SeguimientoScreen(viewModel = viewModel, reporteIdInicial = reporteId)
        }

        composable(Routes.DENUNCIA_NUEVA) {
            val viewModel = DenunciaViewModel(denunciaRepo, connectivityObserver)
            DenunciaScreen(viewModel = viewModel)
        }
    }
}
