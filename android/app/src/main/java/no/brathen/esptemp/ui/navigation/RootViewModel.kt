package no.brathen.esptemp.ui.navigation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import no.brathen.esptemp.data.auth.AccountService
import no.brathen.esptemp.data.auth.AuthRepository
import no.brathen.esptemp.data.auth.AuthState
import no.brathen.esptemp.data.push.FcmTokenRepository

class RootViewModel(
    authRepository: AuthRepository,
    private val accountService: AccountService,
    private val fcmTokenRepository: FcmTokenRepository,
) : ViewModel() {

    val authState = authRepository.authState
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), AuthState.Loading)

    private var handledUid: String? = null

    /** Once per sign-in: unify the account, then register the FCM token. */
    fun onSignedIn(uid: String) {
        if (handledUid == uid) return
        handledUid = uid
        viewModelScope.launch {
            accountService.resolve()
            fcmTokenRepository.uploadCurrentToken()
        }
    }

    fun onSignedOut() {
        handledUid = null
    }
}
