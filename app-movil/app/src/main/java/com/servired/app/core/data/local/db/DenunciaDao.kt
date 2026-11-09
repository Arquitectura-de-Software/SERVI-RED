package com.servired.app.core.data.local.db

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.servired.app.core.data.local.entity.DenunciaEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface DenunciaDao {

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertOrIgnore(denuncia: DenunciaEntity)

    @Query("SELECT * FROM denuncia WHERE pendienteSync = 1")
    suspend fun getPendientes(): List<DenunciaEntity>

    @Query("SELECT * FROM denuncia WHERE id = :id LIMIT 1")
    suspend fun getById(id: String): DenunciaEntity?

    @Query("SELECT * FROM denuncia WHERE seguimientoHash = :hash LIMIT 1")
    suspend fun getByHash(hash: String): DenunciaEntity?

    @Query("UPDATE denuncia SET estado = :estado WHERE id = :id")
    suspend fun updateEstado(id: String, estado: String)

    @Query("UPDATE denuncia SET pendienteSync = 0 WHERE id = :id")
    suspend fun marcarSincronizado(id: String)

    @Query("UPDATE denuncia SET intentos = intentos + 1 WHERE id = :id")
    suspend fun incrementarIntentos(id: String)

    @Query("SELECT * FROM denuncia ORDER BY creadoEn DESC")
    fun getAll(): Flow<List<DenunciaEntity>>
}
