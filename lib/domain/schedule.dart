/// How a reminder decides when to fire.
enum ReminderMode {
  /// Every [ReminderSchedule.intervalMinutes] inside the active window.
  interval,

  /// At each of [ReminderSchedule.fixedTimes].
  fixedTimes,
}

/// A time of day, stored as minutes since midnight (0..1439).
typedef MinuteOfDay = int;

const int minutesPerDay = 24 * 60;

/// When a reminder fires. Pure value object; no Flutter or DB dependencies.
///
/// All times are local wall-clock times. Weekdays use [DateTime.monday]
/// (1) through [DateTime.sunday] (7).
class ReminderSchedule {
  const ReminderSchedule({
    required this.mode,
    this.intervalMinutes = 60,
    this.windowStart = 9 * 60,
    this.windowEnd = 18 * 60,
    this.weekdays = allWeekdays,
    this.fixedTimes = const [],
  });

  static const Set<int> allWeekdays = {1, 2, 3, 4, 5, 6, 7};

  final ReminderMode mode;
  final int intervalMinutes;

  /// Active window for [ReminderMode.interval]. If [windowEnd] is not after
  /// [windowStart] the window runs past midnight (e.g. 22:00 to 02:00) and
  /// belongs to the weekday it starts on.
  final MinuteOfDay windowStart;
  final MinuteOfDay windowEnd;

  final Set<int> weekdays;
  final List<MinuteOfDay> fixedTimes;
}

/// Expands a [ReminderSchedule] into concrete upcoming fire times.
///
/// Day arithmetic works on calendar fields rather than adding [Duration]s, so
/// results stay on the intended wall-clock time across DST changes.
class ScheduleCalculator {
  const ScheduleCalculator();

  /// How many days ahead to look before giving up.
  static const int searchDays = 14;

  /// The next [count] fire times strictly after [from], in ascending order.
  /// Returns fewer than [count] if the schedule has nothing in the next
  /// [searchDays] days (for example no weekdays selected).
  List<DateTime> nextFireTimes(
    ReminderSchedule schedule,
    DateTime from, {
    int count = 64,
  }) {
    if (schedule.weekdays.isEmpty) return const [];

    final offsets = _offsetsWithinSession(schedule);
    if (offsets.isEmpty) return const [];

    final results = <DateTime>[];
    // Start one day back so a window that began yesterday and runs past
    // midnight is still considered.
    for (var d = -1; d <= searchDays; d++) {
      final day = DateTime(from.year, from.month, from.day + d);
      if (!schedule.weekdays.contains(day.weekday)) continue;
      for (final minutes in offsets) {
        // DateTime normalises minute overflow into following days.
        final fire = DateTime(day.year, day.month, day.day, 0, minutes);
        if (fire.isAfter(from)) results.add(fire);
      }
    }
    results.sort();
    return results.length > count ? results.sublist(0, count) : results;
  }

  /// Minute offsets from midnight of the session's start day, ascending.
  /// Values may exceed 1439 for sessions that cross midnight.
  List<int> _offsetsWithinSession(ReminderSchedule s) {
    switch (s.mode) {
      case ReminderMode.fixedTimes:
        final times = s.fixedTimes
            .where((t) => t >= 0 && t < minutesPerDay)
            .toSet()
            .toList()
          ..sort();
        return times;
      case ReminderMode.interval:
        final step = s.intervalMinutes < 1 ? 1 : s.intervalMinutes;
        final start = s.windowStart.clamp(0, minutesPerDay - 1);
        var end = s.windowEnd.clamp(0, minutesPerDay - 1);
        if (end <= start) end += minutesPerDay;
        return [for (var m = start; m <= end; m += step) m];
    }
  }
}
