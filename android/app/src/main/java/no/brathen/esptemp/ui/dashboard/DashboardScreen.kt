package no.brathen.esptemp.ui.dashboard

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AccountCircle
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.Lifecycle
import no.brathen.esptemp.R
import no.brathen.esptemp.domain.model.Device
import no.brathen.esptemp.ui.appViewModel
import no.brathen.esptemp.ui.components.ReadingTile
import no.brathen.esptemp.ui.components.TemperatureChart
import no.brathen.esptemp.ui.theme.HumidityBlue
import no.brathen.esptemp.ui.theme.TempOrange
import no.brathen.esptemp.ui.theme.batteryColor
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen(
    onOpenSettings: () -> Unit,
    onOpenAccount: () -> Unit,
    onOpenDevice: (String) -> Unit,
) {
    val vm = appViewModel {
        DashboardViewModel(it.credentialsStore, it.temperatureRepository, it.deviceRepository, it.authRepository)
    }
    val ui by vm.ui.collectAsStateWithLifecycle()

    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { vm.refresh() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.title_dashboard)) },
                navigationIcon = {
                    IconButton(onClick = onOpenAccount) {
                        Icon(Icons.Rounded.AccountCircle, stringResource(R.string.account))
                    }
                },
                actions = {
                    IconButton(onClick = onOpenSettings) {
                        Icon(Icons.Rounded.Settings, stringResource(R.string.settings))
                    }
                },
            )
        },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = ui.refreshing,
            onRefresh = vm::refresh,
            modifier = Modifier.padding(padding).fillMaxSize(),
        ) {
            if (!ui.hasCredentials) {
                SetupNeeded(onOpenSettings)
            } else {
                DashboardContent(ui, onOpenDevice)
            }
        }
    }
}

@Composable
private fun DashboardContent(ui: DashboardUiState, onOpenDevice: (String) -> Unit) {
    var showVolts by remember { mutableStateOf(false) }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                ReadingTile(
                    label = stringResource(R.string.tile_temperature),
                    value = ui.temperature?.let { "%.1f °C".format(it.value) } ?: "—",
                    color = TempOrange,
                    modifier = Modifier.weight(1f),
                )
                ReadingTile(
                    label = stringResource(R.string.tile_humidity),
                    value = ui.humidity?.let { "%.0f %%".format(it.value) } ?: "—",
                    color = HumidityBlue,
                    modifier = Modifier.weight(1f),
                )
            }
        }

        item {
            Text(
                stringResource(R.string.section_alerts),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
        }
        if (ui.devices.isEmpty()) {
            item { Text(stringResource(R.string.no_devices), style = MaterialTheme.typography.bodyMedium) }
        } else {
            items(ui.devices, key = { it.id }) { device ->
                DeviceRow(device, onClick = { onOpenDevice(device.id) })
            }
        }

        item { HorizontalDivider() }

        item { BatteryCard(ui, showVolts, onToggle = { showVolts = !showVolts }) }

        if (ui.history.size >= 2) {
            item {
                Text(stringResource(R.string.chart_last_24h), style = MaterialTheme.typography.titleMedium)
                TemperatureChart(ui.history, Modifier.fillMaxWidth().height(200.dp))
            }
        }

        item {
            ui.temperature?.createdAt?.let {
                Text(
                    stringResource(R.string.last_updated, fmt(it)),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            (ui.load as? LoadState.Failed)?.let {
                Text(it.message, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun DeviceRow(device: Device, onClick: () -> Unit) {
    val subtitle = if (device.thresholds.enabled) {
        "Varsler under ${device.thresholds.minC.roundToInt()}° / over ${device.thresholds.maxC.roundToInt()}°"
    } else {
        stringResource(R.string.alerts_off)
    }
    ListItem(
        headlineContent = { Text(device.name) },
        supportingContent = { Text(subtitle) },
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
    )
}

@Composable
private fun BatteryCard(ui: DashboardUiState, showVolts: Boolean, onToggle: () -> Unit) {
    val percent = ui.batteryPercent?.value
    val volts = ui.batteryVoltage?.value
    val fraction = ((percent ?: 0.0) / 100.0).coerceIn(0.0, 1.0)
    val text = when {
        showVolts && volts != null -> "%.2f V".format(volts)
        percent != null -> "${percent.roundToInt().coerceIn(0, 100)} %"
        else -> "—"
    }
    Card(Modifier.fillMaxWidth().clickable(onClick = onToggle)) {
        Column(Modifier.padding(16.dp)) {
            Text(stringResource(R.string.battery), style = MaterialTheme.typography.labelMedium)
            Text(
                text,
                style = MaterialTheme.typography.titleLarge,
                color = batteryColor(fraction),
            )
            Text(
                stringResource(if (showVolts) R.string.battery_tap_percent else R.string.battery_tap_volts),
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}

@Composable
private fun SetupNeeded(onOpenSettings: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp, androidx.compose.ui.Alignment.CenterVertically),
        horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally,
    ) {
        Text(stringResource(R.string.setup_needed_title), style = MaterialTheme.typography.titleLarge)
        Text(stringResource(R.string.setup_needed_body), style = MaterialTheme.typography.bodyMedium)
        Button(onClick = onOpenSettings) { Text(stringResource(R.string.open_settings)) }
    }
}

private val timeFormatter: DateTimeFormatter = DateTimeFormatter
    .ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
    .withLocale(Locale("no"))
    .withZone(ZoneId.systemDefault())

private fun fmt(instant: Instant): String = timeFormatter.format(instant)
