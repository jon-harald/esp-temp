package no.brathen.esptemp.data.push

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.core.content.getSystemService
import no.brathen.esptemp.R

object NotificationChannels {
    /** Channel id MUST equal the Cloud Function's android.notification.channelId. */
    fun channelId(context: Context): String = context.getString(R.string.temp_alerts_channel_id)

    fun ensure(context: Context) {
        val manager = context.getSystemService<NotificationManager>() ?: return
        val channel = NotificationChannel(
            channelId(context),
            context.getString(R.string.temp_alerts_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = context.getString(R.string.temp_alerts_channel_desc)
        }
        manager.createNotificationChannel(channel)
    }
}
