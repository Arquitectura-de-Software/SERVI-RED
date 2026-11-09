package com.servired.app.core.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "denuncia",
    indices = [Index(value = ["clientRequestId"], unique = true)]
)
data class DenunciaEntity(
    @PrimaryKey val id: String,
    val clientRequestId: String,
    val servicioId: Int,
    val municipioCodigo: String,
    val lat: Double?,
    val lng: Double?,
    val descripcion: String,
    val codigoSeguimiento: String,
    val seguimientoHash: String,
    val estado: String,
    val pendienteSync: Boolean = true,
    val creadoEn: Long = System.currentTimeMillis(),
    val intentos: Int = 0
)
