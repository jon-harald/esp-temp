package no.brathen.esptemp.ui.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import no.brathen.esptemp.ui.LocalAppContainer
import no.brathen.esptemp.ui.dashboard.DashboardScreen
import no.brathen.esptemp.ui.settings.SettingsScreen
import no.brathen.esptemp.ui.thresholds.ThresholdsScreen

@Composable
fun AppNavHost() {
    val container = LocalAppContainer.current
    val navController = rememberNavController()

    // Deep-link: a tapped push sets a pending device id; navigate then clear.
    val pending by container.deepLinkHandler.pending.collectAsStateWithLifecycle()
    LaunchedEffect(pending) {
        val deviceId = pending ?: return@LaunchedEffect
        navController.navigate(Thresholds(deviceId))
        container.deepLinkHandler.clear()
    }

    NavHost(navController = navController, startDestination = Dashboard) {
        composable<Dashboard> {
            DashboardScreen(
                onOpenSettings = { navController.navigate(Settings) },
                onOpenDevice = { navController.navigate(Thresholds(it)) },
            )
        }
        composable<Settings> {
            SettingsScreen(onBack = { navController.popBackStack() })
        }
        composable<Thresholds> { entry ->
            ThresholdsScreen(
                deviceId = entry.toRoute<Thresholds>().deviceId,
                onBack = { navController.popBackStack() },
            )
        }
    }
}
