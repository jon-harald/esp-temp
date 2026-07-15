package no.brathen.esptemp.ui.account

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.launch
import no.brathen.esptemp.data.auth.AuthRepository
import no.brathen.esptemp.data.credentials.CredentialsStore
import no.brathen.esptemp.data.push.FcmTokenRepository

class AccountViewModel(
    private val authRepository: AuthRepository,
    private val fcmTokenRepository: FcmTokenRepository,
    private val credentialsStore: CredentialsStore,
) : ViewModel() {

    val email: String? = authRepository.currentEmail
    val uid: String = authRepository.currentUid.orEmpty()

    /**
     * Full reset for the phone's user: delete + invalidate the FCM token (stops
     * push to this device) while still signed in, wipe the locally stored Adafruit
     * key, then sign out. The account + devices in the cloud are kept.
     */
    fun signOut() {
        viewModelScope.launch {
            fcmTokenRepository.removeCurrentToken()
            credentialsStore.clear()
            authRepository.signOut()
        }
    }
}
