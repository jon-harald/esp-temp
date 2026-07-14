package no.brathen.esptemp.di

import android.content.Context
import android.content.pm.PackageManager
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.functions.FirebaseFunctions
import kotlinx.serialization.json.Json
import no.brathen.esptemp.data.adafruit.AdafruitIoApi
import no.brathen.esptemp.data.adafruit.AdafruitIoClient
import no.brathen.esptemp.data.auth.AccountService
import no.brathen.esptemp.data.auth.AuthRepository
import no.brathen.esptemp.data.credentials.CredentialsStore
import no.brathen.esptemp.data.device.DeviceRepository
import no.brathen.esptemp.data.device.DeviceStateRepository
import no.brathen.esptemp.data.push.FcmTokenRepository
import no.brathen.esptemp.data.temperature.TemperatureRepository
import no.brathen.esptemp.domain.model.AppConfig
import no.brathen.esptemp.ui.navigation.DeepLinkHandler
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory
import java.util.concurrent.TimeUnit

/**
 * Manual DI container held by [no.brathen.esptemp.EspTempApp]. Framework-instantiated
 * entry points (widget worker, FirebaseMessagingService) reach it via the Application,
 * so they share one DataStore + one Adafruit client (mirrors the iOS shared singletons).
 */
class AppContainer(context: Context) {

    private val appContext = context.applicationContext

    // --- Firebase (europe-west1 for callables) ---
    private val auth: FirebaseAuth by lazy { FirebaseAuth.getInstance() }
    private val firestore: FirebaseFirestore by lazy { FirebaseFirestore.getInstance() }
    private val functions: FirebaseFunctions by lazy { FirebaseFunctions.getInstance("europe-west1") }

    // --- Adafruit IO REST ---
    private val json = Json { ignoreUnknownKeys = true }
    private val okHttp = OkHttpClient.Builder()
        .callTimeout(15, TimeUnit.SECONDS)
        .build()
    private val adafruitApi: AdafruitIoApi = Retrofit.Builder()
        .baseUrl(AppConfig.ADAFRUIT_BASE_URL)
        .client(okHttp)
        .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
        .build()
        .create(AdafruitIoApi::class.java)

    val adafruitClient = AdafruitIoClient(adafruitApi)

    // --- Repositories / services ---
    val credentialsStore = CredentialsStore(appContext)
    val temperatureRepository = TemperatureRepository(adafruitClient)
    val deviceRepository = DeviceRepository(firestore)
    val deviceStateRepository = DeviceStateRepository(firestore)
    val authRepository = AuthRepository(auth)
    val accountService = AccountService(functions)
    val fcmTokenRepository = FcmTokenRepository(auth, firestore, appVersion())

    val deepLinkHandler = DeepLinkHandler()

    private fun appVersion(): String = try {
        appContext.packageManager.getPackageInfo(appContext.packageName, 0).versionName ?: "?"
    } catch (_: PackageManager.NameNotFoundException) {
        "?"
    }
}
