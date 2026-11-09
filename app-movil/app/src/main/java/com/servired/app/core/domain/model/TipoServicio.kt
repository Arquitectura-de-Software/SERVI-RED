package com.servired.app.core.domain.model

enum class TipoServicio(val apiValue: String) {
    ENERGIA("energia"),
    GAS("gas"),
    ACUEDUCTO("acueducto"),
    ALCANTARILLADO("alcantarillado"),
    ASEO("aseo");

    companion object {
        fun fromApiValue(value: String): TipoServicio =
            entries.first { it.apiValue == value }
    }
}
