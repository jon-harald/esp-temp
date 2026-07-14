package no.brathen.esptemp

import android.app.Application
import no.brathen.esptemp.data.push.NotificationChannels
import no.brathen.esptemp.di.AppContainer

class EspTempApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        NotificationChannels.ensure(this)
    }
}
