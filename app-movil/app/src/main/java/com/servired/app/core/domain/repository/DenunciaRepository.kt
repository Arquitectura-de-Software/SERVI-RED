package com.servired.app.core.domain.repository

import com.servired.app.core.domain.model.Denuncia
import com.servired.app.core.domain.model.TipoServicio

interface DenunciaRepository {
    suspend fun enviarDenuncia(
        servicio: TipoServicio,
        municipio: String,
        descripcion: String,
        lat: Double?,
        lng: Double?
    ): Result<String>
    suspend fun consultarEstado(codigoSeguimiento: String): Result<Denuncia>
}
