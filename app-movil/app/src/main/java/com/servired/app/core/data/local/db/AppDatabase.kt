package com.servired.app.core.data.local.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import com.servired.app.core.data.local.entity.DenunciaEntity
import com.servired.app.core.data.local.entity.ReporteEntity

// Room requiere: implementation("androidx.room:room-runtime:2.6.1") y ksp("androidx.room:room-compiler:2.6.1")
@Database(
    entities = [ReporteEntity::class, DenunciaEntity::class],
    version = 1,
    exportSchema = false
)
abstract class AppDatabase : RoomDatabase() {

    abstract fun reporteDao(): ReporteDao
    abstract fun denunciaDao(): DenunciaDao

    companion object {
        @Volatile
        private var INSTANCE: AppDatabase? = null

        fun getInstance(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "servired.db"
                ).build().also { INSTANCE = it }
            }
        }
    }
}
