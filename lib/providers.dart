import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database.dart';
import 'domain/progress.dart';

/// Overridden in main() with the opened database.
final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('databaseProvider must be overridden');
});

final exercisesProvider = StreamProvider<List<Exercise>>(
  (ref) => ref.watch(databaseProvider).watchExercises(),
);

final remindersProvider = StreamProvider<List<ReminderWithExercises>>(
  (ref) => ref.watch(databaseProvider).watchReminders(),
);

/// Bumped when the app returns to the foreground so day-based providers roll
/// over at midnight.
class DayTick extends Notifier<DateTime> {
  @override
  DateTime build() => dayOf(DateTime.now());

  void refresh() => state = dayOf(DateTime.now());
}

final dayTickProvider = NotifierProvider<DayTick, DateTime>(DayTick.new);

/// The day the Today screen is showing. `null` means "follow today", so the
/// screen rolls over at midnight; set when the user navigates to a past day.
class SelectedDay extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void select(DateTime day) {
    final today = dayOf(DateTime.now());
    final picked = dayOf(day);
    final earliest = earliestLoggableDay(DateTime.now());
    if (picked.isAfter(today)) return;
    state = picked.isBefore(earliest) ? earliest : (picked == today ? null : picked);
  }

  void previous() {
    final current = ref.read(viewedDayProvider);
    select(DateTime(current.year, current.month, current.day - 1));
  }

  void next() {
    final current = ref.read(viewedDayProvider);
    select(DateTime(current.year, current.month, current.day + 1));
  }

  void backToToday() => state = null;
}

final selectedDayProvider =
    NotifierProvider<SelectedDay, DateTime?>(SelectedDay.new);

/// The calendar day being viewed (today unless the user went back).
final viewedDayProvider = Provider<DateTime>(
  (ref) => ref.watch(selectedDayProvider) ?? ref.watch(dayTickProvider),
);

/// Logs for the viewed day, newest first.
final viewedDayLogsProvider = StreamProvider<List<LogEntry>>((ref) {
  final day = ref.watch(viewedDayProvider);
  return ref.watch(databaseProvider).watchLogsForDay(day);
});

/// About a year of logs, for streaks, charts and past-day edits.
final recentLogsProvider = StreamProvider<List<LogEntry>>((ref) {
  final day = ref.watch(dayTickProvider);
  final since = DateTime(day.year, day.month, day.day - 399);
  return ref.watch(databaseProvider).watchLogsSince(since);
});

/// Logged total per exercise id for the viewed day.
final viewedTotalsProvider = Provider<Map<int, int>>((ref) {
  final logs = ref.watch(viewedDayLogsProvider).value ?? const [];
  final totals = <int, int>{};
  for (final l in logs) {
    totals[l.exerciseId] = (totals[l.exerciseId] ?? 0) + l.amount;
  }
  return totals;
});

final streakProvider = Provider<({int current, int longest})>((ref) {
  final logs = ref.watch(recentLogsProvider).value ?? const [];
  final exercises = ref.watch(exercisesProvider).value ?? const [];
  final goals = {for (final e in exercises) e.id: e.dailyGoal};
  final active = activeDays(
    logs.map((l) => LogRecord(l.exerciseId, l.amount, l.loggedAt)),
    goals,
  );
  final now = DateTime.now();
  return (current: currentStreak(active, now), longest: longestStreak(active));
});
