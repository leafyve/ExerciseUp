import 'package:exercise_up/domain/schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const calc = ScheduleCalculator();

  // Wednesday 2026-10-07 08:00 local.
  final wed8am = DateTime(2026, 10, 7, 8);

  List<String> hhmm(List<DateTime> times) => times
      .map((t) =>
          '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}')
      .toList();

  group('interval mode', () {
    test('fires every N minutes from window start through window end', () {
      const s = ReminderSchedule(
        mode: ReminderMode.interval,
        intervalMinutes: 120,
        windowStart: 9 * 60,
        windowEnd: 17 * 60,
      );
      expect(hhmm(calc.nextFireTimes(s, wed8am, count: 5)),
          ['10/7 09:00', '10/7 11:00', '10/7 13:00', '10/7 15:00', '10/7 17:00']);
    });

    test('rolls over to the next day after the window closes', () {
      const s = ReminderSchedule(
        mode: ReminderMode.interval,
        intervalMinutes: 180,
        windowStart: 9 * 60,
        windowEnd: 15 * 60,
      );
      final from = DateTime(2026, 10, 7, 15, 30);
      expect(hhmm(calc.nextFireTimes(s, from, count: 2)),
          ['10/8 09:00', '10/8 12:00']);
    });

    test('is strictly after "from"', () {
      const s = ReminderSchedule(
        mode: ReminderMode.interval,
        intervalMinutes: 60,
        windowStart: 9 * 60,
        windowEnd: 12 * 60,
      );
      final from = DateTime(2026, 10, 7, 10);
      expect(hhmm(calc.nextFireTimes(s, from, count: 2)),
          ['10/7 11:00', '10/7 12:00']);
    });

    test('window crossing midnight keeps firing into the next morning', () {
      const s = ReminderSchedule(
        mode: ReminderMode.interval,
        intervalMinutes: 60,
        windowStart: 22 * 60,
        windowEnd: 2 * 60,
      );
      final from = DateTime(2026, 10, 7, 21);
      expect(hhmm(calc.nextFireTimes(s, from, count: 5)),
          ['10/7 22:00', '10/7 23:00', '10/8 00:00', '10/8 01:00', '10/8 02:00']);
    });

    test('midnight-crossing window started yesterday still counts', () {
      const s = ReminderSchedule(
        mode: ReminderMode.interval,
        intervalMinutes: 60,
        windowStart: 22 * 60,
        windowEnd: 2 * 60,
      );
      final from = DateTime(2026, 10, 8, 0, 30);
      expect(hhmm(calc.nextFireTimes(s, from, count: 2)),
          ['10/8 01:00', '10/8 02:00']);
    });

    test('interval longer than the window fires once per day at window start',
        () {
      const s = ReminderSchedule(
        mode: ReminderMode.interval,
        intervalMinutes: 600,
        windowStart: 9 * 60,
        windowEnd: 10 * 60,
      );
      expect(hhmm(calc.nextFireTimes(s, wed8am, count: 2)),
          ['10/7 09:00', '10/8 09:00']);
    });

    test('non-positive interval is treated as one minute, not an infinite loop',
        () {
      const s = ReminderSchedule(
        mode: ReminderMode.interval,
        intervalMinutes: 0,
        windowStart: 9 * 60,
        windowEnd: 9 * 60 + 2,
      );
      expect(hhmm(calc.nextFireTimes(s, wed8am, count: 3)),
          ['10/7 09:00', '10/7 09:01', '10/7 09:02']);
    });
  });

  group('weekdays', () {
    test('skips unselected days', () {
      // Mon, Wed, Fri only.
      const s = ReminderSchedule(
        mode: ReminderMode.fixedTimes,
        fixedTimes: [12 * 60],
        weekdays: {DateTime.monday, DateTime.wednesday, DateTime.friday},
      );
      final from = DateTime(2026, 10, 7, 13); // Wed after noon
      expect(hhmm(calc.nextFireTimes(s, from, count: 3)),
          ['10/9 12:00', '10/12 12:00', '10/14 12:00']);
    });

    test('empty weekday set yields nothing', () {
      const s = ReminderSchedule(
        mode: ReminderMode.fixedTimes,
        fixedTimes: [12 * 60],
        weekdays: {},
      );
      expect(calc.nextFireTimes(s, wed8am), isEmpty);
    });

    test('midnight-crossing window uses the weekday it starts on', () {
      // Only Wednesday selected: Wed 22:00 -> Thu 02:00 fires, Thu 22:00 does not.
      const s = ReminderSchedule(
        mode: ReminderMode.interval,
        intervalMinutes: 120,
        windowStart: 22 * 60,
        windowEnd: 2 * 60,
        weekdays: {DateTime.wednesday},
      );
      final times = calc.nextFireTimes(s, wed8am, count: 4);
      expect(hhmm(times.take(3).toList()), ['10/7 22:00', '10/8 00:00', '10/8 02:00']);
      expect(times[3].day, 14); // next Wednesday, not Thursday
    });
  });

  group('fixed times', () {
    test('fires at each time, sorted and de-duplicated', () {
      const s = ReminderSchedule(
        mode: ReminderMode.fixedTimes,
        fixedTimes: [17 * 60 + 30, 8 * 60 + 30, 12 * 60, 12 * 60],
      );
      expect(hhmm(calc.nextFireTimes(s, DateTime(2026, 10, 7, 7), count: 4)),
          ['10/7 08:30', '10/7 12:00', '10/7 17:30', '10/8 08:30']);
    });

    test('ignores out-of-range times', () {
      const s = ReminderSchedule(
        mode: ReminderMode.fixedTimes,
        fixedTimes: [-5, 1440, 9999, 9 * 60],
      );
      expect(hhmm(calc.nextFireTimes(s, wed8am, count: 2)),
          ['10/7 09:00', '10/8 09:00']);
    });

    test('no times yields nothing', () {
      const s = ReminderSchedule(mode: ReminderMode.fixedTimes);
      expect(calc.nextFireTimes(s, wed8am), isEmpty);
    });
  });

  test('count caps the result', () {
    const s = ReminderSchedule(
      mode: ReminderMode.interval,
      intervalMinutes: 1,
      windowStart: 0,
      windowEnd: 1439,
    );
    expect(calc.nextFireTimes(s, wed8am, count: 10), hasLength(10));
  });

  test('results are strictly ascending', () {
    const s = ReminderSchedule(
      mode: ReminderMode.interval,
      intervalMinutes: 90,
      windowStart: 21 * 60,
      windowEnd: 3 * 60,
    );
    final times = calc.nextFireTimes(s, wed8am, count: 40);
    for (var i = 1; i < times.length; i++) {
      expect(times[i].isAfter(times[i - 1]), isTrue);
    }
  });
}
