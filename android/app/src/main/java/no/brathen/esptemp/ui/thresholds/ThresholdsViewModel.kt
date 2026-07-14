package no.brathen.esptemp.ui.thresholds

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import no.brathen.esptemp.data.auth.AuthRepository
import no.brathen.esptemp.data.device.DeviceRepository
import no.brathen.esptemp.data.device.DeviceStateRepository
import no.brathen.esptemp.domain.model.DeviceState
import no.brathen.esptemp.domain.model.DeviceThresholds

data class ThresholdsUiState(
    val deviceName: String = "",
    val enabled: Boolean = true,
    val minC: Double = DeviceThresholds.fallback.minC,
    val maxC: Double = DeviceThresholds.fallback.maxC,
    val state: DeviceState? = null,
    val saved: Boolean = false,
) {
    val valid: Boolean get() = minC < maxC
}

private const val STEP = 0.5
private const val MAX_LOWER = -20.0
private const val MAX_UPPER = 60.0
private const val MIN_LOWER = -40.0
private const val MIN_UPPER = 40.0

class ThresholdsViewModel(
    private val deviceId: String,
    private val deviceRepository: DeviceRepository,
    deviceStateRepository: DeviceStateRepository,
    authRepository: AuthRepository,
) : ViewModel() {

    private val _ui = MutableStateFlow(ThresholdsUiState())
    val ui = _ui.asStateFlow()

    private var seeded = false

    init {
        authRepository.currentUid?.let { uid ->
            viewModelScope.launch {
                deviceRepository.devices(uid).collect { list ->
                    val device = list.firstOrNull { it.id == deviceId } ?: return@collect
                    _ui.update { s ->
                        if (seeded) {
                            s.copy(deviceName = device.name)
                        } else {
                            seeded = true
                            s.copy(
                                deviceName = device.name,
                                enabled = device.thresholds.enabled,
                                minC = device.thresholds.minC,
                                maxC = device.thresholds.maxC,
                            )
                        }
                    }
                }
            }
        }
        viewModelScope.launch {
            deviceStateRepository.state(deviceId).collect { st -> _ui.update { it.copy(state = st) } }
        }
    }

    fun setEnabled(enabled: Boolean) = _ui.update { it.copy(enabled = enabled, saved = false) }

    fun incMax() = _ui.update { it.copy(maxC = (it.maxC + STEP).coerceIn(MAX_LOWER, MAX_UPPER), saved = false) }
    fun decMax() = _ui.update { it.copy(maxC = (it.maxC - STEP).coerceIn(MAX_LOWER, MAX_UPPER), saved = false) }
    fun incMin() = _ui.update { it.copy(minC = (it.minC + STEP).coerceIn(MIN_LOWER, MIN_UPPER), saved = false) }
    fun decMin() = _ui.update { it.copy(minC = (it.minC - STEP).coerceIn(MIN_LOWER, MIN_UPPER), saved = false) }

    fun save() {
        val s = _ui.value
        if (!s.valid) return
        viewModelScope.launch {
            deviceRepository.updateThresholds(
                deviceId,
                DeviceThresholds(minC = s.minC, maxC = s.maxC, enabled = s.enabled),
            )
            _ui.update { it.copy(saved = true) }
        }
    }
}
