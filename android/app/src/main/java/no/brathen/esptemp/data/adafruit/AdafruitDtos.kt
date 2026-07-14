package no.brathen.esptemp.data.adafruit

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Adafruit IO returns numeric feed values as strings; we keep them as strings in
 * the DTO and parse to Double in the client, matching the iOS `Double(raw)` guard.
 */
@Serializable
data class FeedDto(
    @SerialName("last_value") val lastValue: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
)

@Serializable
data class DataPointDto(
    val value: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
)
