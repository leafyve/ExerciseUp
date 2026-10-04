import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../data/database.dart';
import '../domain/models.dart';
import '../domain/progress.dart';

const _providerName = 'com.enle.exerciseup.ExerciseWidgetProvider';

/// Pushes today's summary to the home-screen widget.
class WidgetSync {
  const WidgetSync._();

  /// Makes every log change, from any isolate, refresh the widget.
  static void install() => AppDatabase.onLogsChanged = push;

  /// The exercise the widget's quick-log button logs: the one logged most
  /// recently, or the first exercise if nothing has been logged yet.
  static Future<Exercise?> quickExercise(AppDatabase db) async {
    final exercises = await db.getExercises();
    if (exercises.isEmpty) return null;
    final now = DateTime.now();
    final logs = await db.getLogsSince(DateTime(now.year, now.month, now.day - 30));
    for (final l in logs.reversed) {
      final match = exercises.where((e) => e.id == l.exerciseId);
      if (match.isNotEmpty) return match.first;
    }
    return exercises.first;
  }

  static Future<void> push(AppDatabase db) async {
    try {
      final now = DateTime.now();
      final exercises = await db.getExercises();
      final logs =
          await db.getLogsSince(DateTime(now.year, now.month, now.day - 399));
      final byId = {for (final e in exercises) e.id: e};

      final today = dayOf(now);
      final todayTotals = <int, int>{};
      for (final l in logs) {
        if (dayOf(l.loggedAt) == today) {
          todayTotals[l.exerciseId] = (todayTotals[l.exerciseId] ?? 0) + l.amount;
        }
      }
      final top = todayTotals.entries
          .where((e) => byId.containsKey(e.key))
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final summary = top.isEmpty
          ? 'Nothing logged yet today'
          : top.take(3).map((e) {
              final ex = byId[e.key]!;
              return ex.unit == ExerciseUnit.seconds
                  ? '${e.value} sec ${ex.name}'
                  : '${e.value} × ${ex.name}';
            }).join('  ·  ');

      final active = activeDays(
        logs.map((l) => LogRecord(l.exerciseId, l.amount, l.loggedAt)),
        {for (final e in exercises) e.id: e.dailyGoal},
      );
      final streak = currentStreak(active, now);
      final quick = await quickExercise(db);

      await HomeWidget.saveWidgetData<String>('summary', summary);
      await HomeWidget.saveWidgetData<String>(
          'streak', streak == 0 ? 'No streak yet' : '$streak-day streak');
      await HomeWidget.saveWidgetData<String>(
          'quick_label',
          quick == null
              ? 'Open app'
              : '+ ${quick.defaultAmount} ${quick.name}');
      await HomeWidget.updateWidget(qualifiedAndroidName: _providerName);
    } catch (e, st) {
      // The widget is a convenience; never let it break logging itself.
      debugPrint('Widget refresh failed: $e\n$st');
    }
  }
}

/// Runs in a background isolate when the widget's quick-log button is tapped.
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  if (uri?.host != 'quicklog') return;
  DartPluginRegistrant.ensureInitialized();
  WidgetSync.install();
  final db = AppDatabase();
  try {
    final exercise = await WidgetSync.quickExercise(db);
    if (exercise != null) {
      // Triggers a widget refresh through AppDatabase.onLogsChanged.
      await db.logExercise(exercise.id, exercise.defaultAmount);
    }
  } finally {
    await db.close();
  }
}
