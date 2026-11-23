package com.servired.app.feature.mapa

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import com.servired.app.core.domain.model.TipoServicio

object MarkerBitmapHelper {

    fun crearIconoServicio(context: Context, servicio: TipoServicio, esIncidente: Boolean): Drawable {
        val density = context.resources.displayMetrics.density
        val size = (36 * density).toInt()
        val bitmap = Bitmap.createBitmap(size, (size * 1.25f).toInt(), Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val pinColor = when (servicio) {
            TipoServicio.ACUEDUCTO -> Color.parseColor("#0288D1") // Azul agua
            TipoServicio.ENERGIA -> Color.parseColor("#F57C00") // Ámbar eléctrico
            TipoServicio.GAS -> Color.parseColor("#D32F2F") // Rojo gas
            TipoServicio.ALCANTARILLADO -> Color.parseColor("#7B1FA2") // Púrpura
            TipoServicio.ASEO -> Color.parseColor("#388E3C") // Verde bosque
        }

        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = pinColor
            style = Paint.Style.FILL
        }

        // Forma de gota / pin de mapa invertido
        val r = size / 2f
        val path = Path().apply {
            arcTo(0f, 0f, size.toFloat(), size.toFloat(), 180f, 180f, true)
            lineTo(r, size * 1.25f)
            close()
        }
        canvas.drawPath(path, paint)

        // Borde blanco nítido
        val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.STROKE
            strokeWidth = 2.5f * density
        }
        canvas.drawPath(path, borderPaint)

        // Círculo blanco interno
        val innerCirclePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.FILL
        }
        canvas.drawCircle(r, r, r * 0.52f, innerCirclePaint)

        // Punto o indicador central
        val centerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = if (esIncidente) Color.parseColor("#B71C1C") else pinColor
            style = Paint.Style.FILL
        }
        canvas.drawCircle(r, r, r * 0.35f, centerPaint)

        return BitmapDrawable(context.resources, bitmap)
    }

    fun crearIconoUsuario(context: Context): Drawable {
        val density = context.resources.displayMetrics.density
        val size = (32 * density).toInt()
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val r = size / 2f

        // Halo semitransparente exterior
        val haloPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#332196F3")
            style = Paint.Style.FILL
        }
        canvas.drawCircle(r, r, r, haloPaint)

        // Anillo blanco
        val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.FILL
        }
        canvas.drawCircle(r, r, r * 0.68f, borderPaint)

        // Círculo azul GPS de alta visibilidad
        val centerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#1976D2")
            style = Paint.Style.FILL
        }
        canvas.drawCircle(r, r, r * 0.52f, centerPaint)

        return BitmapDrawable(context.resources, bitmap)
    }
}
