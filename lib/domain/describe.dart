import 'models.dart';
import 'schedule.dart';

/// "Every day", "Weekdays", "Weekends", or "Mon, Wed, Fri".
String describeWeekdays(Set<int> days) {
  if (days.length == 7) return 'Every day';
  if (days.isEmpty) return 'No days';
  if (days.length == 5 && !days.contains(6) && !days.contains(7)) {
    return 'Weekdays';
  }
  if (days.length == 2 && days.containsAll({6, 7})) return 'Weekends';
  final sorted = days.toList()..sort();
  return sorted.map((d) => weekdayShortNames[d - 1]).join(', ');
}

/// One-line summary of when a reminder fires.
String describeSchedule(ReminderSchedule s) {
  final days = describeWeekdays(s.weekdays);
  switch (s.mode) {
    case ReminderMode.interval:
      return 'Every ${formatInterval(s.intervalMinutes)}, '
          '${formatMinuteOfDay(s.windowStart)}–${formatMinuteOfDay(s.windowEnd)} · $days';
    case ReminderMode.fixedTimes:
      final times = ([...s.fixedTimes]..sort()).map(formatMinuteOfDay);
      return '${times.isEmpty ? 'No times set' : times.join(', ')} · $days';
  }
}
