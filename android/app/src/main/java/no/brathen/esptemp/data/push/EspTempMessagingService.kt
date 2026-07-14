package no.brathen.esptemp.data.push

import android.app.PendingIntent
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.runBlocking
import no.brathen.esptemp.EspTempApp
import no.brathen.esptemp.MainActivity
import no.brathen.esptemp.R

/**
 * Receives FCM tokens + foreground messages (mirrors iOS AppDelegate receive side).
 * Callbacks run on a background thread, so the quick token write may block.
 */
class EspTempMessagingService : FirebaseMessagingService() {

    override fun onNewToken(token: String) {
        val container = (application as EspTempApp).container
        runBlocking { runCatching { container.fcmTokenRepository.setToken(token) } }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        // FCM only invokes this in the foreground for notification+data messages;
        // backgrounded ones are auto-posted by the system. Post it ourselves here so
        // the deep-link PendingIntent (deviceId) is attached in the foreground case.
        val deviceId = message.data["deviceId"]
        val title = message.notification?.title ?: message.data["title"] ?: getString(R.string.app_name)
        val body = message.notification?.body ?: message.data["body"].orEmpty()
        showNotification(title, body, deviceId)
    }

    private fun showNotification(title: String, body: String, deviceId: String?) {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (deviceId != null) putExtra(EXTRA_DEVICE_ID, deviceId)
        }
        val pending = PendingIntent.getActivity(
            this,
            deviceId?.hashCode() ?: 0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(this, NotificationChannels.channelId(this))
            .setSmallIcon(R.drawable.ic_stat_temp)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()

        val manager = NotificationManagerCompat.from(this)
        if (manager.areNotificationsEnabled()) {
            manager.notify(deviceId?.hashCode() ?: NOTIFICATION_ID, notification)
        }
    }

    companion object {
        const val EXTRA_DEVICE_ID = "deviceId"
        private const val NOTIFICATION_ID = 1001
    }
}
