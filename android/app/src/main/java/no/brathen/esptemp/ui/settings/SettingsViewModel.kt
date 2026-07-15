package no.brathen.esptemp.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import no.brathen.esptemp.data.auth.AuthRepository
import no.brathen.esptemp.data.credentials.CredentialsStore
import no.brathen.esptemp.data.push.FcmTokenRepository
import no.brathen.esptemp.domain.model.AppConfig

data class SettingsUiState(
    val username: String = "",
    val apiKey: String = "",
    val temperatureFeed: String = AppConfig.DEFAULT_TEMPERATURE_FEED,
    val humidityFeed: String = AppConfig.DEFAULT_HUMIDITY_FEED,
    val saved: Boolean = false,
) {
    val canSave: Boolean get() = username.isNotBlank() && apiKey.isNotBlank()
}

class SettingsViewModel(
    private val credentialsStore: CredentialsStore,
    private val authRepository: AuthRepository,
    private val fcmTokenRepository: FcmTokenRepository,
) : ViewModel() {

    private val _ui = MutableStateFlow(SettingsUiState())
    val ui = _ui.asStateFlow()

    val email: String? = authRepository.currentEmail
    val uid: String = authRepository.currentUid.orEmpty()

    init {
        viewModelScope.launch {
            credentialsStore.credentials.first()?.let { c ->
                _ui.update {
                    it.copy(
                        username = c.username,
                        apiKey = c.apiKey,
                        temperatureFeed = c.temperatureFeed,
                        humidityFeed = c.humidityFeed,
                    )
                }
            }
        }
    }

    fun onUsername(v: String) = _ui.update { it.copy(username = v) }
    fun onApiKey(v: String) = _ui.update { it.copy(apiKey = v) }
    fun onTemperatureFeed(v: String) = _ui.update { it.copy(temperatureFeed = v) }
    fun onHumidityFeed(v: String) = _ui.update { it.copy(humidityFeed = v) }

    fun save() {
        val s = _ui.value
        if (!s.canSave) return
        viewModelScope.launch {
            credentialsStore.save(s.username, s.apiKey, s.temperatureFeed, s.humidityFeed)
            _ui.update { it.copy(saved = true) }
        }
    }

    /**
     * Full reset for the phone's user: delete + invalidate the FCM token (stops
     * push to this device), wipe the locally stored Adafruit key, then sign out.
     * The cloud account + devices are kept.
     */
    fun signOut() {
        viewModelScope.launch {
            fcmTokenRepository.removeCurrentToken()
            credentialsStore.clear()
            authRepository.signOut()
        }
    }
}
