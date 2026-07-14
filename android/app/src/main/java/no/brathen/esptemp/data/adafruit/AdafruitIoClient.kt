package no.brathen.esptemp.data.adafruit

import no.brathen.esptemp.domain.model.AppConfig
import no.brathen.esptemp.domain.model.Credentials
import no.brathen.esptemp.domain.model.FeedReading
import retrofit2.HttpException
import java.io.IOException
import java.time.Instant
import java.time.OffsetDateTime

/** Norwegian-facing failures, mirroring the iOS error copy. */
sealed class AdafruitError(message: String) : Exception(message) {
    data class Http(val code: Int) : AdafruitError("HTTP-feil $code (sjekk nøkkel/feed).")
    data object Empty : AdafruitError("Feeden har ingen verdi ennå.")
    data object Network : AdafruitError("Nettverksfeil. Prøv igjen.")
    data object Decoding : AdafruitError("Ugyldig svar fra Adafruit IO.")
}

/** Thin wrapper over [AdafruitIoApi] that maps DTOs → domain + errors → [AdafruitError]. */
class AdafruitIoClient(private val api: AdafruitIoApi) {

    suspend fun latest(cred: Credentials, feed: String): FeedReading {
        val dto = call { api.latest(cred.username, feed, cred.apiKey) }
        val value = dto.lastValue?.toDoubleOrNull() ?: throw AdafruitError.Empty
        return FeedReading(value = value, createdAt = parseInstant(dto.updatedAt))
    }

    suspend fun history(
        cred: Credentials,
        feed: String,
        limit: Int = AppConfig.HISTORY_LIMIT,
    ): List<FeedReading> {
        val points = call { api.history(cred.username, feed, limit, cred.apiKey) }
        return points
            .mapNotNull { p ->
                val v = p.value?.toDoubleOrNull() ?: return@mapNotNull null
                FeedReading(value = v, createdAt = parseInstant(p.createdAt))
            }
            .sortedBy { it.createdAt } // oldest → newest, like iOS
    }

    private inline fun <T> call(block: () -> T): T =
        try {
            block()
        } catch (e: HttpException) {
            throw AdafruitError.Http(e.code())
        } catch (e: IOException) {
            throw AdafruitError.Network
        }

    private fun parseInstant(raw: String?): Instant {
        if (raw == null) return Instant.now()
        return runCatching { Instant.parse(raw) }
            .recoverCatching { OffsetDateTime.parse(raw).toInstant() }
            .getOrDefault(Instant.now())
    }
}
