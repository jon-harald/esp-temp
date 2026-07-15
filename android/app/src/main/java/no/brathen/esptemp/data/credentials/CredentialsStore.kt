package no.brathen.esptemp.data.credentials

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import no.brathen.esptemp.domain.model.AppConfig
import no.brathen.esptemp.domain.model.Credentials

private val Context.dataStore by preferencesDataStore(name = "credentials")

/**
 * Adafruit IO credentials in a Preferences DataStore (mirrors iOS CredentialStore).
 * The AIO key is read-only, so plaintext DataStore is acceptable (same rationale as
 * the iOS App Group). Shared in-process with the widget worker via AppContainer.
 */
class CredentialsStore(private val context: Context) {

    val credentials: Flow<Credentials?> = context.dataStore.data.map { p ->
        val username = p[USERNAME]?.trim().orEmpty()
        val apiKey = p[API_KEY]?.trim().orEmpty()
        if (username.isEmpty() || apiKey.isEmpty()) return@map null
        Credentials(
            username = username,
            apiKey = apiKey,
            temperatureFeed = p[TEMP_FEED]?.takeIf { it.isNotBlank() } ?: AppConfig.DEFAULT_TEMPERATURE_FEED,
            humidityFeed = p[HUM_FEED]?.takeIf { it.isNotBlank() } ?: AppConfig.DEFAULT_HUMIDITY_FEED,
        )
    }

    /** Wipes stored Adafruit credentials (used on sign-out / reset). */
    suspend fun clear() {
        context.dataStore.edit { it.clear() }
    }

    suspend fun save(
        username: String,
        apiKey: String,
        temperatureFeed: String,
        humidityFeed: String,
    ) {
        context.dataStore.edit { p ->
            p[USERNAME] = username.trim()
            p[API_KEY] = apiKey.trim()
            p[TEMP_FEED] = temperatureFeed.trim().ifBlank { AppConfig.DEFAULT_TEMPERATURE_FEED }
            p[HUM_FEED] = humidityFeed.trim().ifBlank { AppConfig.DEFAULT_HUMIDITY_FEED }
        }
    }

    private companion object {
        val USERNAME = stringPreferencesKey("aio.username")
        val API_KEY = stringPreferencesKey("aio.apiKey")
        val TEMP_FEED = stringPreferencesKey("aio.tempFeed")
        val HUM_FEED = stringPreferencesKey("aio.humFeed")
    }
}
