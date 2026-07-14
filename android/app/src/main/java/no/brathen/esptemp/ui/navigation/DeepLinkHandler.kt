package no.brathen.esptemp.ui.navigation

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Holds a pending deep-link device id from a tapped push (mirrors iOS
 * PushService.pendingDeepLinkDeviceId). The nav host navigates once the device is
 * loaded, then clears it.
 */
class DeepLinkHandler {
    private val _pending = MutableStateFlow<String?>(null)
    val pending: StateFlow<String?> = _pending.asStateFlow()

    fun set(deviceId: String) { _pending.value = deviceId }
    fun clear() { _pending.value = null }
}
