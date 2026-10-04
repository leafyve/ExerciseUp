/// One logged set, independent of the database layer.
class LogRecord {
  const LogRecord(this.exerciseId, this.amount, this.at);
  final int exerciseId;
  final int amount;
  final DateTime at;
}

DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// Timestamp to store when logging a set while viewing [day].
///
/// Today uses [now] as is. A past day keeps [now]'s time of day so sets
/// logged in sequence stay in order, but never lands in the future.
DateTime logTimestampFor(DateTime day, DateTime now) {
  final target = dayOf(day);
  if (target == dayOf(now)) return now;
  return DateTime(target.year, target.month, target.day, now.hour, now.minute,
      now.second);
}

/// Earliest day the app lets you go back to when adding past sets.
DateTime earliestLoggableDay(DateTime now) =>
    DateTime(now.year, now.month, now.day - 364);

/// Total logged per exercise for each calendar day.
Map<DateTime, Map<int, int>> totalsByDay(Iterable<LogRecord> logs) {
  final result = <DateTime, Map<int, int>>{};
  for (final l in logs) {
    final day = result.putIfAbsent(dayOf(l.at), () => {});
    day[l.exerciseId] = (day[l.exerciseId] ?? 0) + l.amount;
  }
  return result;
}

/// Days that count towards a streak.
///
/// If any exercise has a goal (> 0), a day counts when every goal-bearing
/// exercise reached its goal. With no goals set, any logged activity counts.
Set<DateTime> activeDays(
  Iterable<LogRecord> logs,
  Map<int, int> dailyGoals,
) {
  final goals = Map.of(dailyGoals)..removeWhere((_, g) => g <= 0);
  final days = totalsByDay(logs);
  final active = <DateTime>{};
  days.forEach((day, totals) {
    if (goals.isEmpty) {
      if (totals.values.any((v) => v > 0)) active.add(day);
    } else if (goals.entries.every((g) => (totals[g.key] ?? 0) >= g.value)) {
      active.add(day);
    }
  });
  return active;
}

/// Consecutive active days ending today. If today is not yet active the
/// streak is measured up to yesterday, so it does not read 0 all morning.
int currentStreak(Set<DateTime> active, DateTime now) {
  var day = dayOf(now);
  if (!active.contains(day)) day = DateTime(day.year, day.month, day.day - 1);
  var streak = 0;
  while (active.contains(day)) {
    streak++;
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return streak;
}

/// Longest run of consecutive active days.
int longestStreak(Set<DateTime> active) {
  final sorted = active.toList()..sort();
  var best = 0;
  var run = 0;
  DateTime? prev;
  for (final d in sorted) {
    final isNext =
        prev != null && DateTime(prev.year, prev.month, prev.day + 1) == d;
    run = isNext ? run + 1 : 1;
    if (run > best) best = run;
    prev = d;
  }
  return best;
}
