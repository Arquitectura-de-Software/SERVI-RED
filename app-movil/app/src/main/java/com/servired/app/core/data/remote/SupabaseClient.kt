package com.servired.app.core.data.remote

import com.servired.app.core.data.remote.dto.DenunciaDto
import com.servired.app.core.data.remote.dto.DenunciaResponseDto
import com.servired.app.core.data.remote.dto.ReporteDto
import com.servired.app.core.data.remote.dto.ReporteResponseDto
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.engine.android.Android
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.defaultRequest
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.parameter
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json

object SupabaseClient {

    private const val SUPABASE_URL = "https://your-project.supabase.co"
    private const val SUPABASE_ANON_KEY = "your-anon-key"

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    private val httpClient = HttpClient(Android) {
        install(ContentNegotiation) {
            json(json)
        }
        defaultRequest {
            header("apikey", SUPABASE_ANON_KEY)
            header("Authorization", "Bearer $SUPABASE_ANON_KEY")
        }
    }

    suspend fun registrarReporte(dto: ReporteDto): Result<ReporteResponseDto> {
        return runCatching {
            val response = httpClient.post("$SUPABASE_URL/rest/v1/rpc/registrar_reporte") {
                contentType(ContentType.Application.Json)
                setBody(dto)
            }
            if (response.status == HttpStatusCode.OK || response.status == HttpStatusCode.Created) {
                response.body<ReporteResponseDto>()
            } else {
                throw Exception("Error HTTP ${response.status.value} al registrar reporte")
            }
        }.onFailure { e ->
            Result.failure<ReporteResponseDto>(Exception("Error de red: ${e.message}", e))
        }
    }

    suspend fun registrarDenuncia(dto: DenunciaDto): Result<String> {
        return runCatching {
            val response = httpClient.post("$SUPABASE_URL/rest/v1/rpc/registrar_denuncia") {
                contentType(ContentType.Application.Json)
                setBody(dto)
            }
            if (response.status == HttpStatusCode.OK || response.status == HttpStatusCode.Created) {
                response.body<DenunciaResponseDto>().id
            } else {
                throw Exception("Error HTTP ${response.status.value} al registrar denuncia")
            }
        }.onFailure { e ->
            Result.failure<String>(Exception("Error de red: ${e.message}", e))
        }
    }

    suspend fun consultarReporte(reporteId: String): Result<ReporteDto> {
        return runCatching {
            val response = httpClient.get("$SUPABASE_URL/rest/v1/reporte") {
                parameter("id", "eq.$reporteId")
                parameter("select", "*")
                parameter("limit", "1")
            }
            if (response.status == HttpStatusCode.OK) {
                val list = response.body<List<ReporteDto>>()
                list.firstOrNull() ?: throw Exception("Reporte no encontrado")
            } else {
                throw Exception("Error HTTP ${response.status.value} al consultar reporte")
            }
        }.onFailure { e ->
            Result.failure<ReporteDto>(Exception("Error de red: ${e.message}", e))
        }
    }

    suspend fun consultarDenunciaPorHash(hash: String): Result<DenunciaDto> {
        return runCatching {
            val response = httpClient.get("$SUPABASE_URL/rest/v1/denuncia") {
                parameter("seguimiento_hash", "eq.$hash")
                parameter("select", "*")
                parameter("limit", "1")
            }
            if (response.status == HttpStatusCode.OK) {
                val list = response.body<List<DenunciaDto>>()
                list.firstOrNull() ?: throw Exception("Denuncia no encontrada")
            } else {
                throw Exception("Error HTTP ${response.status.value} al consultar denuncia")
            }
        }.onFailure { e ->
            Result.failure<DenunciaDto>(Exception("Error de red: ${e.message}", e))
        }
    }
}
