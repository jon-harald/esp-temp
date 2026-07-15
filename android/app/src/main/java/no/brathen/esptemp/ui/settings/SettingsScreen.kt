package no.brathen.esptemp.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.Logout
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import no.brathen.esptemp.R
import no.brathen.esptemp.ui.appViewModel
import no.brathen.esptemp.widget.TempWidgetRefresh

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(onBack: () -> Unit) {
    val vm = appViewModel {
        SettingsViewModel(it.credentialsStore, it.authRepository, it.fcmTokenRepository)
    }
    val ui by vm.ui.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    var showConfirm by remember { mutableStateOf(false) }

    LaunchedEffect(ui.saved) {
        if (ui.saved) {
            TempWidgetRefresh.requestNow(context) // replaces iOS WidgetCenter.reloadAllTimelines()
            onBack()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.settings)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Rounded.ArrowBack, stringResource(R.string.cancel))
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // --- Adafruit IO ---
            OutlinedTextField(
                value = ui.username,
                onValueChange = vm::onUsername,
                label = { Text(stringResource(R.string.aio_username)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = ui.apiKey,
                onValueChange = vm::onApiKey,
                label = { Text(stringResource(R.string.aio_key)) },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = ui.temperatureFeed,
                onValueChange = vm::onTemperatureFeed,
                label = { Text(stringResource(R.string.feed_temperature)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = ui.humidityFeed,
                onValueChange = vm::onHumidityFeed,
                label = { Text(stringResource(R.string.feed_humidity)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Button(onClick = vm::save, enabled = ui.canSave, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.save))
            }

            HorizontalDivider(Modifier.padding(vertical = 8.dp))

            // --- Konto ---
            Text(stringResource(R.string.account), style = MaterialTheme.typography.titleMedium)
            vm.email?.takeIf { it.isNotBlank() }?.let {
                Column {
                    Text(stringResource(R.string.email), style = MaterialTheme.typography.labelMedium)
                    Text(it, style = MaterialTheme.typography.bodyLarge)
                }
            }
            Column {
                Text(stringResource(R.string.user_id), style = MaterialTheme.typography.labelMedium)
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(vm.uid, style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
                    IconButton(onClick = { clipboard.setText(AnnotatedString(vm.uid)) }) {
                        Icon(Icons.Rounded.ContentCopy, stringResource(R.string.copy))
                    }
                }
            }
            OutlinedButton(onClick = { showConfirm = true }, modifier = Modifier.fillMaxWidth()) {
                Icon(
                    Icons.AutoMirrored.Rounded.Logout,
                    contentDescription = null,
                    modifier = Modifier.padding(end = 8.dp),
                )
                Text(stringResource(R.string.sign_out))
            }
        }
    }

    if (showConfirm) {
        AlertDialog(
            onDismissRequest = { showConfirm = false },
            title = { Text(stringResource(R.string.sign_out_confirm_title)) },
            text = { Text(stringResource(R.string.sign_out_confirm_body)) },
            confirmButton = {
                TextButton(onClick = {
                    showConfirm = false
                    vm.signOut()
                }) { Text(stringResource(R.string.sign_out)) }
            },
            dismissButton = {
                TextButton(onClick = { showConfirm = false }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }
}
