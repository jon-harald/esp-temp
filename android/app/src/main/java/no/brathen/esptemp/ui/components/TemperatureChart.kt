package no.brathen.esptemp.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.StrokeCap
import no.brathen.esptemp.domain.model.FeedReading
import no.brathen.esptemp.ui.theme.TempOrange

/** Minimal orange polyline of the last-24h history (Compose analog of the iOS LineMark). */
@Composable
fun TemperatureChart(history: List<FeedReading>, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        if (history.size < 2) return@Canvas
        val values = history.map { it.value }
        val minV = values.min()
        val maxV = values.max()
        val range = (maxV - minV).takeIf { it > 0.0 } ?: 1.0

        val lastIndex = history.size - 1
        val path = Path()
        history.forEachIndexed { i, reading ->
            val x = size.width * i / lastIndex
            val norm = ((reading.value - minV) / range).toFloat()
            val y = size.height - norm * size.height
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        drawPath(path, color = TempOrange, style = Stroke(width = 4f, cap = StrokeCap.Round))
    }
}
