package no.brathen.esptemp

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import no.brathen.esptemp.data.push.EspTempMessagingService
import no.brathen.esptemp.ui.LocalAppContainer
import no.brathen.esptemp.ui.navigation.RootScreen
import no.brathen.esptemp.ui.theme.EspTempTheme

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        handleDeepLink(intent)

        val container = (application as EspTempApp).container
        setContent {
            EspTempTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background,
                ) {
                    CompositionLocalProvider(LocalAppContainer provides container) {
                        RootScreen()
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleDeepLink(intent)
    }

    private fun handleDeepLink(intent: Intent?) {
        val deviceId = intent?.getStringExtra(EspTempMessagingService.EXTRA_DEVICE_ID) ?: return
        (application as EspTempApp).container.deepLinkHandler.set(deviceId)
    }
}
