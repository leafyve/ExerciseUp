import 'schedule.dart';

/// What an exercise's amount is counted in.
enum ExerciseUnit {
  reps('reps'),
  seconds('sec');

  const ExerciseUnit(this.label);
  final String label;
}

/// Encodes a set of weekdays (1=Mon..7=Sun) as a bitmask for storage.
int weekdaysToMask(Set<int> weekdays) =>
    weekdays.fold(0, (mask, d) => mask | (1 << (d - 1)));

Set<int> weekdaysFromMask(int mask) =>
    {for (var d = 1; d <= 7; d++) if (mask & (1 << (d - 1)) != 0) d};

/// Fixed times are stored as a comma-separated list of minutes-of-day.
String fixedTimesToText(List<MinuteOfDay> times) => times.join(',');

List<MinuteOfDay> fixedTimesFromText(String text) => text.isEmpty
    ? const []
    : text.split(',').map(int.parse).toList(growable: false);

/// "9:05 AM"-style label for a minute-of-day, 12-hour clock.
String formatMinuteOfDay(MinuteOfDay m) {
  final h24 = (m ~/ 60) % 24;
  final min = m % 60;
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  final suffix = h24 < 12 ? 'AM' : 'PM';
  return '$h12:${min.toString().padLeft(2, '0')} $suffix';
}

/// "2 hours", "90 minutes", "1 hour 30 min".
String formatInterval(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final hours = h == 1 ? '1 hour' : '$h hours';
  return m == 0 ? hours : '$hours $m min';
}

const weekdayShortNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
