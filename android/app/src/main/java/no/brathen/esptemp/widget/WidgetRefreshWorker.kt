package no.brathen.esptemp.widget

import android.content.Context
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.appwidget.updateAll
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.flow.first
import no.brathen.esptemp.EspTempApp

/**
 * Fetches the latest temperature + humidity and writes them into every widget's
 * Glance state, then re-renders. Reuses the app's shared CredentialsStore +
 * AdafruitIoClient from AppContainer (same process). Best-effort, like iOS `try?`.
 */
class WidgetRefreshWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val container = (applicationContext as EspTempApp).container
        val creds = container.credentialsStore.credentials.first() ?: return Result.success()

        val temperature = runCatching { container.adafruitClient.latest(creds, creds.temperatureFeed) }.getOrNull()
        val humidity = runCatching { container.adafruitClient.latest(creds, creds.humidityFeed) }.getOrNull()

        val manager = GlanceAppWidgetManager(applicationContext)
        val ids = manager.getGlanceIds(TempWidget::class.java)
        ids.forEach { id ->
            updateAppWidgetState(applicationContext, id) { prefs ->
                if (temperature != null) {
                    prefs[TempWidget.TEMP_KEY] = temperature.value
                    prefs[TempWidget.UPDATED_AT_KEY] = temperature.createdAt.toEpochMilli()
                }
                if (humidity != null) {
                    prefs[TempWidget.HUM_KEY] = humidity.value
                }
            }
        }
        TempWidget().updateAll(applicationContext)
        return Result.success()
    }
}
