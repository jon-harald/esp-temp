package no.brathen.esptemp.ui.dashboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import no.brathen.esptemp.data.auth.AuthRepository
import no.brathen.esptemp.data.credentials.CredentialsStore
import no.brathen.esptemp.data.device.DeviceRepository
import no.brathen.esptemp.data.temperature.TemperatureRepository
import no.brathen.esptemp.domain.model.Credentials
import no.brathen.esptemp.domain.model.Device
import no.brathen.esptemp.domain.model.FeedReading

sealed interface LoadState {
    data object Idle : LoadState
    data object Loading : LoadState
    data object Loaded : LoadState
    data class Failed(val message: String) : LoadState
}

data class DashboardUiState(
    val hasCredentials: Boolean = false,
    val temperature: FeedReading? = null,
    val humidity: FeedReading? = null,
    val batteryPercent: FeedReading? = null,
    val batteryVoltage: FeedReading? = null,
    val history: List<FeedReading> = emptyList(),
    val load: LoadState = LoadState.Idle,
    val refreshing: Boolean = false,
    val devices: List<Device> = emptyList(),
)

private const val REFRESH_INTERVAL_MS = 30_000L

class DashboardViewModel(
    private val credentialsStore: CredentialsStore,
    private val temperatureRepository: TemperatureRepository,
    deviceRepository: DeviceRepository,
    authRepository: AuthRepository,
) : ViewModel() {

    private val _ui = MutableStateFlow(DashboardUiState())
    val ui = _ui.asStateFlow()

    private var credentials: Credentials? = null

    init {
        authRepository.currentUid?.let { uid ->
            viewModelScope.launch {
                deviceRepository.devices(uid).collect { d -> _ui.update { it.copy(devices = d) } }
            }
        }

        viewModelScope.launch {
            credentialsStore.credentials.collect { creds ->
                credentials = creds
                if (creds == null) {
                    _ui.update { it.copy(hasCredentials = false, load = LoadState.Idle) }
                } else {
                    _ui.update { it.copy(hasCredentials = true) }
                    load(creds, isRefresh = false)
                }
            }
        }

        // Auto-refresh loop (mirrors iOS 30 s task loop).
        viewModelScope.launch {
            while (true) {
                delay(REFRESH_INTERVAL_MS)
                credentials?.let { load(it, isRefresh = true) }
            }
        }
    }

    /** Manual pull-to-refresh + resume trigger. */
    fun refresh() {
        credentials?.let { creds -> viewModelScope.launch { load(creds, isRefresh = true) } }
    }

    private suspend fun load(creds: Credentials, isRefresh: Boolean) {
        _ui.update {
            it.copy(
                load = if (!isRefresh && it.temperature == null) LoadState.Loading else it.load,
                refreshing = isRefresh,
            )
        }
        runCatching { temperatureRepository.load(creds) }
            .onSuccess { snap ->
                _ui.update {
                    it.copy(
                        temperature = snap.temperature,
                        humidity = snap.humidity,
                        batteryPercent = snap.batteryPercent,
                        batteryVoltage = snap.batteryVoltage,
                        history = snap.history,
                        load = LoadState.Loaded,
                        refreshing = false,
                    )
                }
            }
            .onFailure { e ->
                _ui.update {
                    it.copy(load = LoadState.Failed(e.localizedMessage ?: "Ukjent feil"), refreshing = false)
                }
            }
    }
}
