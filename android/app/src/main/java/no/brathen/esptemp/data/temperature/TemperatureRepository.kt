package no.brathen.esptemp.data.temperature

import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import no.brathen.esptemp.data.adafruit.AdafruitIoClient
import no.brathen.esptemp.domain.model.AppConfig
import no.brathen.esptemp.domain.model.Credentials
import no.brathen.esptemp.domain.model.FeedReading

/** One fetch of everything the dashboard shows. */
data class TemperatureSnapshot(
    val temperature: FeedReading?,
    val humidity: FeedReading?,
    val batteryPercent: FeedReading?,
    val batteryVoltage: FeedReading?,
    val history: List<FeedReading>,
)

/**
 * Fans out the dashboard's reads in parallel (mirrors iOS TemperatureStore.refresh).
 * Temperature is required — if it fails the whole load fails; the rest are
 * best-effort (a missing battery feed shouldn't blank the screen).
 */
class TemperatureRepository(private val client: AdafruitIoClient) {

    suspend fun load(cred: Credentials): TemperatureSnapshot = coroutineScope {
        val temp = async { client.latest(cred, cred.temperatureFeed) }
        val humidity = async { optional { client.latest(cred, cred.humidityFeed) } }
        val batteryPercent = async { optional { client.latest(cred, AppConfig.BATTERY_PERCENT_FEED) } }
        val batteryVoltage = async { optional { client.latest(cred, AppConfig.BATTERY_VOLTAGE_FEED) } }
        val history = async {
            runCatching { client.history(cred, cred.temperatureFeed) }.getOrDefault(emptyList())
        }
        TemperatureSnapshot(
            temperature = temp.await(), // may throw AdafruitError → surfaced as failed
            humidity = humidity.await(),
            batteryPercent = batteryPercent.await(),
            batteryVoltage = batteryVoltage.await(),
            history = history.await(),
        )
    }

    private inline fun <T> optional(block: () -> T): T? = runCatching(block).getOrNull()
}
