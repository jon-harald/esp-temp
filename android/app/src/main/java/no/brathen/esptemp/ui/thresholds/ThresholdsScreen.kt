package no.brathen.esptemp.ui.thresholds

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import no.brathen.esptemp.R
import no.brathen.esptemp.domain.model.DeviceState
import no.brathen.esptemp.ui.appViewModel
import no.brathen.esptemp.ui.components.StepperRow
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ThresholdsScreen(deviceId: String, onBack: () -> Unit) {
    val vm = appViewModel {
        ThresholdsViewModel(deviceId, it.deviceRepository, it.deviceStateRepository, it.authRepository)
    }
    val ui by vm.ui.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(ui.deviceName.ifBlank { "Sensor" }) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Rounded.ArrowBack, stringResource(R.string.cancel))
                    }
                },
                actions = {
                    TextButton(onClick = vm::save, enabled = ui.valid && !ui.saved) {
                        Text(stringResource(if (ui.saved) R.string.saved else R.string.save))
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier.padding(padding).fillMaxSize().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(stringResource(R.string.alerts_on), style = MaterialTheme.typography.titleMedium)
                Switch(checked = ui.enabled, onCheckedChange = vm::setEnabled)
            }
            Text(stringResource(R.string.alerts_hint), style = MaterialTheme.typography.bodySmall)

            HorizontalDivider()

            Text(stringResource(R.string.section_limits), style = MaterialTheme.typography.titleMedium)
            StepperRow(
                label = stringResource(R.string.max_label),
                valueText = "%.1f °C".format(ui.maxC),
                onDecrement = vm::decMax,
                onIncrement = vm::incMax,
                enabled = ui.enabled,
            )
            StepperRow(
                label = stringResource(R.string.min_label),
                valueText = "%.1f °C".format(ui.minC),
                onDecrement = vm::decMin,
                onIncrement = vm::incMin,
                enabled = ui.enabled,
            )
            if (!ui.valid) {
                Text(stringResource(R.string.min_below_max), color = MaterialTheme.colorScheme.error)
            }

            ui.state?.let { state ->
                HorizontalDivider()
                Text(stringResource(R.string.section_now), style = MaterialTheme.typography.titleMedium)
                LabeledValue(stringResource(R.string.status), statusText(state.status))
                state.lastReadingValue?.let {
                    LabeledValue(stringResource(R.string.tile_temperature), "%.1f °C".format(it))
                }
                state.lastReadingAt?.let {
                    Text(
                        stringResource(R.string.read_at, fmt(it)),
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        }
    }
}

@Composable
private fun LabeledValue(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = MaterialTheme.typography.bodyMedium)
        Text(value, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun statusText(status: DeviceState.Status): String = stringResource(
    when (status) {
        DeviceState.Status.HIGH -> R.string.status_high
        DeviceState.Status.LOW -> R.string.status_low
        DeviceState.Status.NORMAL -> R.string.status_normal
    }
)

private val timeFormatter: DateTimeFormatter = DateTimeFormatter
    .ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
    .withLocale(Locale("no"))
    .withZone(ZoneId.systemDefault())

private fun fmt(instant: Instant): String = timeFormatter.format(instant)
