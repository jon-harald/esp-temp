package no.brathen.esptemp.ui.navigation

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import no.brathen.esptemp.data.auth.AuthState
import no.brathen.esptemp.ui.appViewModel
import no.brathen.esptemp.ui.signin.SignInScreen

/** Auth gate (mirrors iOS RootView): spinner / sign-in / app. */
@Composable
fun RootScreen() {
    val vm = appViewModel { RootViewModel(it.authRepository, it.accountService, it.fcmTokenRepository) }
    val state by vm.authState.collectAsStateWithLifecycle()

    val notifPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { /* result ignored; alerts still arrive, just silently if denied */ }

    when (val s = state) {
        AuthState.Loading -> Box(Modifier.fillMaxSize(), Alignment.Center) {
            CircularProgressIndicator()
        }

        AuthState.SignedOut -> {
            LaunchedEffect(Unit) { vm.onSignedOut() }
            SignInScreen()
        }

        is AuthState.SignedIn -> {
            LaunchedEffect(s.user.uid) {
                vm.onSignedIn(s.user.uid)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
                }
            }
            AppNavHost()
        }
    }
}
