package no.brathen.esptemp.widget

import android.text.format.DateUtils
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.glance.GlanceModifier
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import androidx.compose.ui.graphics.Color
import no.brathen.esptemp.ui.theme.tempColor

/**
 * Home-screen widget: latest temperature + humidity + "Oppdatert X siden".
 * Renders from Glance state written by [WidgetRefreshWorker] (no network here).
 */
class TempWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: android.content.Context, id: androidx.glance.GlanceId) {
        provideContent { Content() }
    }

    @Composable
    private fun Content() {
        val prefs = currentState<Preferences>()
        val temp = prefs[TEMP_KEY]
        val humidity = prefs[HUM_KEY]
        val updatedAt = prefs[UPDATED_AT_KEY]

        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(Color(0xFF1B1B1F))
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (temp != null) {
                Text(
                    "%.1f°".format(temp),
                    style = TextStyle(
                        fontSize = 30.sp,
                        fontWeight = FontWeight.Bold,
                        color = ColorProvider(tempColor(temp)),
                    ),
                )
                if (humidity != null) {
                    Text("${humidity.toInt()} %", style = TextStyle(fontSize = 13.sp, color = white))
                }
                Text(updatedText(updatedAt), style = TextStyle(fontSize = 11.sp, color = white))
            } else {
                Text("Ingen data", style = TextStyle(fontSize = 14.sp, color = white))
            }
        }
    }

    private fun updatedText(epochMillis: Long?): String {
        if (epochMillis == null || epochMillis <= 0) return "Ingen data"
        val rel = DateUtils.getRelativeTimeSpanString(
            epochMillis,
            System.currentTimeMillis(),
            DateUtils.MINUTE_IN_MILLIS,
        )
        return "Oppdatert $rel"
    }

    companion object {
        val TEMP_KEY = doublePreferencesKey("temp")
        val HUM_KEY = doublePreferencesKey("hum")
        val UPDATED_AT_KEY = longPreferencesKey("updatedAt")
        private val white = ColorProvider(Color(0xFFFFFFFF))
    }
}
