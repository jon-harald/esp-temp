package no.brathen.esptemp.domain.model

import java.time.Instant

/** Server-owned alert state, mirrored from Firestore devices/{id}/state/current. */
data class DeviceState(
    val status: Status,
    val lastReadingValue: Double?,
    val lastReadingAt: Instant?,
) {
    enum class Status { NORMAL, HIGH, LOW;

        companion object {
            fun from(raw: String?): Status = when (raw) {
                "high" -> HIGH
                "low" -> LOW
                else -> NORMAL
            }
        }
    }
}
