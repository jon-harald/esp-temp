package no.brathen.esptemp.domain.model

/** Feed keys published by the firmware to Adafruit IO (mirrors iOS AppConfig). */
object AppConfig {
    const val DEFAULT_TEMPERATURE_FEED = "temperature"
    const val DEFAULT_HUMIDITY_FEED = "humidity"
    const val BATTERY_PERCENT_FEED = "esp-battery-pct"
    const val BATTERY_VOLTAGE_FEED = "esp-battery-v"

    const val ADAFRUIT_BASE_URL = "https://io.adafruit.com/"
    const val HISTORY_LIMIT = 200
}
