package no.brathen.esptemp.domain.model

import java.time.Instant

/** A single Adafruit IO reading (mirrors iOS FeedReading). */
data class FeedReading(
    val value: Double,
    val createdAt: Instant,
)
