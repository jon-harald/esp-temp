package no.brathen.esptemp.ui.account

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.launch
import no.brathen.esptemp.data.auth.AuthRepository
import no.brathen.esptemp.data.push.FcmTokenRepository

class AccountViewModel(
    private val authRepository: AuthRepository,
    private val fcmTokenRepository: FcmTokenRepository,
) : ViewModel() {

    val email: String? = authRepository.currentEmail
    val uid: String = authRepository.currentUid.orEmpty()

    /** Delete the FCM token while still signed in (needs uid), then sign out. */
    fun signOut() {
        viewModelScope.launch {
            fcmTokenRepository.removeCurrentToken()
            authRepository.signOut()
        }
    }
}
