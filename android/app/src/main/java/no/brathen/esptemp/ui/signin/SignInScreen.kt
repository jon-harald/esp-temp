package no.brathen.esptemp.ui.signin

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import no.brathen.esptemp.R
import no.brathen.esptemp.ui.appViewModel

@Composable
fun SignInScreen() {
    val vm = appViewModel { SignInViewModel(it.authRepository) }
    val ui by vm.ui.collectAsStateWithLifecycle()
    val context = LocalContext.current

    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(stringResource(R.string.app_name), style = MaterialTheme.typography.headlineMedium)

        OutlinedButton(
            onClick = { vm.signInWithGoogle(context) },
            enabled = !ui.busy,
        ) {
            Text(stringResource(R.string.sign_in_with_google))
        }

        OutlinedTextField(
            value = ui.email,
            onValueChange = vm::onEmail,
            label = { Text(stringResource(R.string.email)) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
        )
        OutlinedTextField(
            value = ui.password,
            onValueChange = vm::onPassword,
            label = { Text(stringResource(R.string.password)) },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
        )

        Button(onClick = vm::submit, enabled = ui.canSubmit) {
            Text(stringResource(if (ui.isSignUp) R.string.sign_up else R.string.sign_in))
        }
        TextButton(onClick = vm::toggleMode) {
            Text(stringResource(if (ui.isSignUp) R.string.toggle_to_sign_in else R.string.toggle_to_sign_up))
        }

        if (ui.busy) CircularProgressIndicator()
        if (ui.info == "verify_email") {
            Text(stringResource(R.string.verify_email_sent), color = MaterialTheme.colorScheme.primary)
        }
        ui.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    }
}
