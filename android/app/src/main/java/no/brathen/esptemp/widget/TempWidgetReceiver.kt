package no.brathen.esptemp.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver

class TempWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = TempWidget()

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        TempWidgetRefresh.schedulePeriodic(context)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        TempWidgetRefresh.requestNow(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        TempWidgetRefresh.cancel(context)
    }
}
