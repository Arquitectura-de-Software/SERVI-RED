package com.servired.app.core.location

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import androidx.core.content.ContextCompat
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import com.google.android.gms.tasks.Task
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class LocationHelper(private val context: Context) {

    private val fusedLocationClient = LocationServices.getFusedLocationProviderClient(context)

    /**
     * Verifica si la aplicación tiene permiso de ubicación precisa o aproximada.
     */
    fun hasLocationPermission(): Boolean {
        val fineGranted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        val coarseGranted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        return fineGranted || coarseGranted
    }

    /**
     * Verifica si los servicios de ubicación (GPS o Red) están activados en el dispositivo.
     */
    fun isLocationEnabled(): Boolean {
        val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            ?: return false
        return locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
    }

    /**
     * Obtiene la ubicación actual del dispositivo usando FusedLocationProviderClient.
     * 1. Consulta la última ubicación conocida si es reciente (< 60 segundos).
     * 2. Si no hay reciente, solicita una lectura fresca con alta precisión.
     */
    @SuppressLint("MissingPermission")
    suspend fun getCurrentLocation(): Location? {
        if (!hasLocationPermission()) return null

        return try {
            // Intentar con la última ubicación conocida si es fresca
            val last = fusedLocationClient.lastLocation.awaitResult()
            if (last != null && (System.currentTimeMillis() - last.time) < 60_000) {
                return last
            }

            // Solicitar ubicación actual fresca de alta precisión
            val cts = CancellationTokenSource()
            val fresh = fusedLocationClient.getCurrentLocation(
                Priority.PRIORITY_HIGH_ACCURACY,
                cts.token
            ).awaitResult()

            fresh ?: last
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Convierte una Google Task en una función suspendida segura de Coroutines.
     */
    private suspend fun <T> Task<T>.awaitResult(): T? = suspendCancellableCoroutine { continuation ->
        addOnSuccessListener { result ->
            if (continuation.isActive) {
                continuation.resume(result)
            }
        }
        addOnFailureListener { exception ->
            if (continuation.isActive) {
                continuation.resumeWithException(exception)
            }
        }
        addOnCanceledListener {
            if (continuation.isActive) {
                continuation.cancel()
            }
        }
    }
}
