package com.enle.exerciseup

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class ExerciseWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.exercise_widget).apply {
                setTextViewText(
                    R.id.widget_summary,
                    widgetData.getString("summary", null) ?: "Open ExerciseUp to get started",
                )
                setTextViewText(
                    R.id.widget_streak,
                    widgetData.getString("streak", null) ?: "",
                )
                setTextViewText(
                    R.id.widget_quick_log,
                    widgetData.getString("quick_label", null) ?: "Open app",
                )
                // Tap anywhere: open the app.
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
                // Tap the button: log in the background, no app launch.
                setOnClickPendingIntent(
                    R.id.widget_quick_log,
                    HomeWidgetBackgroundIntent.getBroadcast(
                        context,
                        Uri.parse("exerciseup://quicklog"),
                    ),
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
