package com.servired.app.core.data.local.db

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.servired.app.core.data.local.entity.ReporteEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ReporteDao {

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertOrIgnore(reporte: ReporteEntity)

    @Query("SELECT * FROM reporte WHERE pendienteSync = 1")
    suspend fun getPendientes(): List<ReporteEntity>

    @Query("SELECT * FROM reporte WHERE id = :id LIMIT 1")
    suspend fun getById(id: String): ReporteEntity?

    @Query("UPDATE reporte SET estado = :estado WHERE id = :id")
    suspend fun updateEstado(id: String, estado: String)

    @Query("UPDATE reporte SET pendienteSync = 0 WHERE id = :id")
    suspend fun marcarSincronizado(id: String)

    @Query("UPDATE reporte SET intentosSincronizacion = intentosSincronizacion + 1 WHERE id = :id")
    suspend fun incrementarIntentos(id: String)

    @Query("SELECT * FROM reporte ORDER BY creadoEn DESC")
    fun getAll(): Flow<List<ReporteEntity>>
}
