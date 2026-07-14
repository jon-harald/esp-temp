package no.brathen.esptemp.ui.signin

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import no.brathen.esptemp.data.auth.AuthRepository
import no.brathen.esptemp.data.auth.getGoogleIdToken

data class SignInUiState(
    val email: String = "",
    val password: String = "",
    val isSignUp: Boolean = false,
    val busy: Boolean = false,
    val error: String? = null,
    val info: String? = null,
) {
    val canSubmit: Boolean get() = email.isNotBlank() && password.length >= 6 && !busy
}

class SignInViewModel(private val authRepository: AuthRepository) : ViewModel() {

    private val _ui = MutableStateFlow(SignInUiState())
    val ui = _ui.asStateFlow()

    fun onEmail(value: String) = _ui.update { it.copy(email = value, error = null) }
    fun onPassword(value: String) = _ui.update { it.copy(password = value, error = null) }
    fun toggleMode() = _ui.update { it.copy(isSignUp = !it.isSignUp, error = null, info = null) }

    fun submit() {
        val s = _ui.value
        if (!s.canSubmit) return
        viewModelScope.launch {
            _ui.update { it.copy(busy = true, error = null, info = null) }
            runCatching {
                if (s.isSignUp) authRepository.signUp(s.email, s.password)
                else authRepository.signIn(s.email, s.password)
            }.onSuccess {
                _ui.update {
                    it.copy(busy = false, info = if (s.isSignUp) "verify_email" else null)
                }
            }.onFailure { e ->
                _ui.update { it.copy(busy = false, error = e.localizedMessage) }
            }
        }
    }

    fun signInWithGoogle(context: Context) {
        viewModelScope.launch {
            _ui.update { it.copy(busy = true, error = null) }
            runCatching {
                val token = getGoogleIdToken(context)
                authRepository.signInWithGoogle(token)
            }.onFailure { e ->
                _ui.update { it.copy(busy = false, error = e.localizedMessage) }
            }.onSuccess {
                _ui.update { it.copy(busy = false) }
            }
        }
    }
}
