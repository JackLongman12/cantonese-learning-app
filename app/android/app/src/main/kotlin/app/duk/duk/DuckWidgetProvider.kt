package app.duk.duk

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widget: characters due today and characters known well, saved by the app
 * (lib/platform/home_widget_sync.dart). Tapping it opens DuckLearn.
 */
class DuckWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val due = widgetData.getInt("due", -1)
        val known = widgetData.getInt("known", 0)
        val headline = when {
            due < 0 -> "Open DuckLearn to start"
            due == 0 -> "All caught up"
            due == 1 -> "1 character to review"
            else -> "$due characters to review"
        }
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.duck_widget).apply {
                setTextViewText(R.id.widget_headline, headline)
                setTextViewText(R.id.widget_known, "$known known well")
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
