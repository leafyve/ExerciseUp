import 'package:exercise_up/domain/progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DateTime d(int day, [int hour = 12]) => DateTime(2026, 10, day, hour);
  final today = DateTime(2026, 10, 10, 15);

  group('activeDays', () {
    test('with no goals any log counts', () {
      final active = activeDays([LogRecord(1, 5, d(8))], {});
      expect(active, {DateTime(2026, 10, 8)});
    });

    test('with goals every goal must be met, summing across logs', () {
      final logs = [
        LogRecord(1, 10, d(8, 9)),
        LogRecord(1, 10, d(8, 18)), // push-ups 20/20
        LogRecord(2, 15, d(8)), // squats 15/30
        LogRecord(1, 20, d(9)),
        LogRecord(2, 30, d(9)),
      ];
      final active = activeDays(logs, {1: 20, 2: 30});
      expect(active, {DateTime(2026, 10, 9)});
    });

    test('exercises with goal 0 are ignored', () {
      final active = activeDays([LogRecord(1, 20, d(8))], {1: 20, 2: 0});
      expect(active, {DateTime(2026, 10, 8)});
    });

    test('zero-amount logs do not count when there are no goals', () {
      expect(activeDays([LogRecord(1, 0, d(8))], {}), isEmpty);
    });
  });

  group('currentStreak', () {
    Set<DateTime> days(List<int> ds) => {for (final x in ds) DateTime(2026, 10, x)};

    test('counts consecutive days ending today', () {
      expect(currentStreak(days([8, 9, 10]), today), 3);
    });

    test('is not broken by an inactive today; measured to yesterday', () {
      expect(currentStreak(days([7, 8, 9]), today), 3);
    });

    test('is 0 once a full day was missed', () {
      expect(currentStreak(days([5, 6, 7]), today), 0);
    });

    test('stops at the first gap', () {
      expect(currentStreak(days([5, 7, 8, 9, 10]), today), 4);
    });

    test('works across a month boundary', () {
      final active = {
        DateTime(2026, 9, 29),
        DateTime(2026, 9, 30),
        DateTime(2026, 10, 1),
      };
      expect(currentStreak(active, DateTime(2026, 10, 1, 8)), 3);
    });
  });

  group('logTimestampFor', () {
    final now = DateTime(2026, 10, 10, 15, 42, 7);

    test('today keeps the exact current time', () {
      expect(logTimestampFor(DateTime(2026, 10, 10), now), now);
    });

    test('a past day keeps the time of day on that date', () {
      expect(logTimestampFor(DateTime(2026, 10, 7), now),
          DateTime(2026, 10, 7, 15, 42, 7));
    });

    test('ignores any time component on the day argument', () {
      expect(logTimestampFor(DateTime(2026, 10, 7, 23, 59), now),
          DateTime(2026, 10, 7, 15, 42, 7));
    });

    test('a logged past day counts as that day for activeDays', () {
      final at = logTimestampFor(DateTime(2026, 10, 9), now);
      expect(activeDays([LogRecord(1, 5, at)], {}), {DateTime(2026, 10, 9)});
    });
  });

  test('earliestLoggableDay is a year back', () {
    expect(earliestLoggableDay(DateTime(2026, 10, 10, 9)),
        DateTime(2025, 10, 11));
  });

  test('longestStreak finds the best run', () {
    final active = {
      DateTime(2026, 10, 1),
      DateTime(2026, 10, 2),
      DateTime(2026, 10, 4),
      DateTime(2026, 10, 5),
      DateTime(2026, 10, 6),
      DateTime(2026, 10, 9),
    };
    expect(longestStreak(active), 3);
    expect(longestStreak({}), 0);
  });
}
