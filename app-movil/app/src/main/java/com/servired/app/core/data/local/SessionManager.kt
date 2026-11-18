package com.servired.app.core.data.local

import android.content.Context
import android.content.SharedPreferences

class SessionManager(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun guardarSesion(accessToken: String, refreshToken: String?, userId: String?) {
        prefs.edit()
            .putString(KEY_ACCESS_TOKEN, accessToken)
            .putString(KEY_REFRESH_TOKEN, refreshToken)
            .putString(KEY_USER_ID, userId)
            .putLong(KEY_SAVED_AT, System.currentTimeMillis())
            .apply()
    }

    fun obtenerAccessToken(): String? = prefs.getString(KEY_ACCESS_TOKEN, null)

    fun obtenerRefreshToken(): String? = prefs.getString(KEY_REFRESH_TOKEN, null)

    fun obtenerUserId(): String? = prefs.getString(KEY_USER_ID, null)

    fun haySesion(): Boolean = !obtenerAccessToken().isNullOrBlank()

    fun limpiarSesion() {
        prefs.edit().clear().apply()
    }

    companion object {
        private const val PREFS_NAME = "servired_auth_prefs"
        private const val KEY_ACCESS_TOKEN = "supabase_access_token"
        private const val KEY_REFRESH_TOKEN = "supabase_refresh_token"
        private const val KEY_USER_ID = "supabase_user_id"
        private const val KEY_SAVED_AT = "supabase_token_saved_at"

        @Volatile
        private var INSTANCE: SessionManager? = null

        fun getInstance(context: Context): SessionManager {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: SessionManager(context.applicationContext).also { INSTANCE = it }
            }
        }
    }
}
