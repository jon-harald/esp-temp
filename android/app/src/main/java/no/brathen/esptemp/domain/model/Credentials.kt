package no.brathen.esptemp.domain.model

/** Adafruit IO credentials + feed names (mirrors iOS Credentials). */
data class Credentials(
    val username: String,
    val apiKey: String,
    val temperatureFeed: String,
    val humidityFeed: String,
)
