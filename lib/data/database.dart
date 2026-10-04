import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../domain/models.dart';
import '../domain/schedule.dart';

part 'database.g.dart';

class Exercises extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  IntColumn get unit => intEnum<ExerciseUnit>()();

  /// Key into the UI's icon map (see ui/exercise_icons.dart).
  TextColumn get icon => text().withDefault(const Constant('fitness'))();

  /// Amount pre-filled when logging or adding to a reminder.
  IntColumn get defaultAmount => integer().withDefault(const Constant(10))();

  /// Daily goal in the exercise's unit; 0 means no goal.
  IntColumn get dailyGoal => integer().withDefault(const Constant(0))();

  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

class Reminders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get mode => intEnum<ReminderMode>()();
  IntColumn get intervalMinutes => integer().withDefault(const Constant(60))();
  IntColumn get windowStart => integer().withDefault(const Constant(540))();
  IntColumn get windowEnd => integer().withDefault(const Constant(1080))();

  /// Bitmask, bit 0 = Monday. See [weekdaysToMask].
  IntColumn get weekdaysMask => integer().withDefault(const Constant(127))();

  /// Comma-separated minutes-of-day. See [fixedTimesToText].
  TextColumn get fixedTimes => text().withDefault(const Constant(''))();

  /// Android notification sound: 'default', 'silent', or a system sound key.
  TextColumn get sound => text().withDefault(const Constant('default'))();
  BoolColumn get vibrate => boolean().withDefault(const Constant(true))();
}

class ReminderExercises extends Table {
  IntColumn get reminderId =>
      integer().references(Reminders, #id, onDelete: KeyAction.cascade)();
  IntColumn get exerciseId =>
      integer().references(Exercises, #id, onDelete: KeyAction.cascade)();

  /// Amount to do each time this reminder fires, in the exercise's unit.
  IntColumn get target => integer()();

  @override
  Set<Column> get primaryKey => {reminderId, exerciseId};
}

@DataClassName('LogEntry')
class Logs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get exerciseId =>
      integer().references(Exercises, #id, onDelete: KeyAction.cascade)();
  IntColumn get reminderId => integer()
      .nullable()
      .references(Reminders, #id, onDelete: KeyAction.setNull)();
  IntColumn get amount => integer()();
  DateTimeColumn get loggedAt => dateTime()();
}

/// A reminder together with the exercises it asks for.
class ReminderWithExercises {
  const ReminderWithExercises(this.reminder, this.items);

  final Reminder reminder;
  final List<ReminderItem> items;

  ReminderSchedule get schedule => ReminderSchedule(
        mode: reminder.mode,
        intervalMinutes: reminder.intervalMinutes,
        windowStart: reminder.windowStart,
        windowEnd: reminder.windowEnd,
        weekdays: weekdaysFromMask(reminder.weekdaysMask),
        fixedTimes: fixedTimesFromText(reminder.fixedTimes),
      );
}

class ReminderItem {
  const ReminderItem(this.exercise, this.target);
  final Exercise exercise;
  final int target;
}

/// Editable fields for creating or updating a reminder.
class ReminderDraft {
  const ReminderDraft({
    required this.name,
    required this.schedule,
    required this.items,
    this.enabled = true,
    this.sound = 'default',
    this.vibrate = true,
  });

  final String name;
  final ReminderSchedule schedule;
  final bool enabled;
  final String sound;
  final bool vibrate;

  /// exerciseId -> target amount.
  final Map<int, int> items;
}

@DriftDatabase(tables: [Exercises, Reminders, ReminderExercises, Logs])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ??
            driftDatabase(
              name: 'exerciseup',
              // Notification actions run in a background isolate and must
              // write to the same database the UI is watching.
              native: const DriftNativeOptions(shareAcrossIsolates: true),
            ));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedExercises();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _seedExercises() async {
    Future<void> add(String name, ExerciseUnit unit, String icon, int amount) =>
        into(exercises).insert(ExercisesCompanion.insert(
          name: name,
          unit: unit,
          icon: Value(icon),
          defaultAmount: Value(amount),
        ));

    await add('Push-ups', ExerciseUnit.reps, 'pushup', 10);
    await add('Squats', ExerciseUnit.reps, 'squat', 15);
    await add('Sit-ups', ExerciseUnit.reps, 'situp', 15);
    await add('Plank', ExerciseUnit.seconds, 'plank', 30);
    await add('Lunges', ExerciseUnit.reps, 'lunge', 12);
    await add('Jumping jacks', ExerciseUnit.reps, 'jack', 20);
    await add('Burpees', ExerciseUnit.reps, 'burpee', 8);
  }

  // ---------------------------------------------------------------- exercises

  Stream<List<Exercise>> watchExercises() =>
      (select(exercises)
            ..where((e) => e.archived.equals(false))
            ..orderBy([(e) => OrderingTerm.asc(e.id)]))
          .watch();

  Future<int> addExercise({
    required String name,
    required ExerciseUnit unit,
    required String icon,
    required int defaultAmount,
  }) =>
      into(exercises).insert(ExercisesCompanion.insert(
        name: name,
        unit: unit,
        icon: Value(icon),
        defaultAmount: Value(defaultAmount),
        isCustom: const Value(true),
      ));

  Future<void> updateExercise(
    int id, {
    String? name,
    int? defaultAmount,
    int? dailyGoal,
    String? icon,
  }) =>
      (update(exercises)..where((e) => e.id.equals(id))).write(
        ExercisesCompanion(
          name: name == null ? const Value.absent() : Value(name),
          defaultAmount:
              defaultAmount == null ? const Value.absent() : Value(defaultAmount),
          dailyGoal:
              dailyGoal == null ? const Value.absent() : Value(dailyGoal),
          icon: icon == null ? const Value.absent() : Value(icon),
        ),
      );

  /// Custom exercises are archived rather than deleted so history survives.
  Future<void> archiveExercise(int id) =>
      (update(exercises)..where((e) => e.id.equals(id)))
          .write(const ExercisesCompanion(archived: Value(true)));

  Future<List<Exercise>> getExercises() =>
      (select(exercises)
            ..where((e) => e.archived.equals(false))
            ..orderBy([(e) => OrderingTerm.asc(e.id)]))
          .get();

  // --------------------------------------------------------------------- logs

  /// Called after logs are added or removed, in whichever isolate made the
  /// change. The app installs this to refresh the home-screen widget.
  static Future<void> Function(AppDatabase db)? onLogsChanged;

  Future<int> logExercise(
    int exerciseId,
    int amount, {
    int? reminderId,
    DateTime? at,
  }) async {
    final id = await into(logs).insert(LogsCompanion.insert(
      exerciseId: exerciseId,
      reminderId: Value(reminderId),
      amount: amount,
      loggedAt: at ?? DateTime.now(),
    ));
    await onLogsChanged?.call(this);
    return id;
  }

  Future<void> deleteLog(int id) async {
    await (delete(logs)..where((l) => l.id.equals(id))).go();
    await onLogsChanged?.call(this);
  }

  /// Logs from [since] onwards, oldest first.
  Future<List<LogEntry>> getLogsSince(DateTime since) =>
      (select(logs)
            ..where((l) => l.loggedAt.isBiggerOrEqualValue(since))
            ..orderBy([(l) => OrderingTerm.asc(l.loggedAt)]))
          .get();

  /// Logs recorded on the local calendar day containing [day], newest first.
  Stream<List<LogEntry>> watchLogsForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    return (select(logs)
          ..where((l) => l.loggedAt.isBiggerOrEqualValue(start))
          ..where((l) => l.loggedAt.isSmallerThanValue(end))
          ..orderBy([(l) => OrderingTerm.desc(l.loggedAt)]))
        .watch();
  }

  /// Logs from [since] onwards, oldest first. Used for streaks and charts.
  Stream<List<LogEntry>> watchLogsSince(DateTime since) =>
      (select(logs)
            ..where((l) => l.loggedAt.isBiggerOrEqualValue(since))
            ..orderBy([(l) => OrderingTerm.asc(l.loggedAt)]))
          .watch();

  // ---------------------------------------------------------------- reminders

  Stream<List<ReminderWithExercises>> watchReminders() {
    final query = select(reminders).join([
      leftOuterJoin(reminderExercises,
          reminderExercises.reminderId.equalsExp(reminders.id)),
      leftOuterJoin(
          exercises, exercises.id.equalsExp(reminderExercises.exerciseId)),
    ])
      ..orderBy([OrderingTerm.asc(reminders.id)]);
    return query.watch().map(_groupReminders);
  }

  Future<List<ReminderWithExercises>> getReminders() async {
    final query = select(reminders).join([
      leftOuterJoin(reminderExercises,
          reminderExercises.reminderId.equalsExp(reminders.id)),
      leftOuterJoin(
          exercises, exercises.id.equalsExp(reminderExercises.exerciseId)),
    ])
      ..orderBy([OrderingTerm.asc(reminders.id)]);
    return _groupReminders(await query.get());
  }

  Future<ReminderWithExercises?> getReminder(int id) async =>
      (await getReminders()).where((r) => r.reminder.id == id).firstOrNull;

  List<ReminderWithExercises> _groupReminders(List<TypedResult> rows) {
    final byId = <int, Reminder>{};
    final items = <int, List<ReminderItem>>{};
    for (final row in rows) {
      final r = row.readTable(reminders);
      byId[r.id] = r;
      final list = items.putIfAbsent(r.id, () => []);
      final ex = row.readTableOrNull(exercises);
      final link = row.readTableOrNull(reminderExercises);
      if (ex != null && link != null) list.add(ReminderItem(ex, link.target));
    }
    return [
      for (final r in byId.values) ReminderWithExercises(r, items[r.id]!),
    ];
  }

  Future<int> saveReminder(ReminderDraft draft, {int? id}) =>
      transaction(() async {
        final s = draft.schedule;
        final companion = RemindersCompanion(
          name: Value(draft.name),
          enabled: Value(draft.enabled),
          mode: Value(s.mode),
          intervalMinutes: Value(s.intervalMinutes),
          windowStart: Value(s.windowStart),
          windowEnd: Value(s.windowEnd),
          weekdaysMask: Value(weekdaysToMask(s.weekdays)),
          fixedTimes: Value(fixedTimesToText(s.fixedTimes)),
          sound: Value(draft.sound),
          vibrate: Value(draft.vibrate),
        );
        late final int reminderId;
        if (id == null) {
          reminderId = await into(reminders).insert(companion);
        } else {
          reminderId = id;
          await (update(reminders)..where((r) => r.id.equals(id)))
              .write(companion);
          await (delete(reminderExercises)
                ..where((r) => r.reminderId.equals(id)))
              .go();
        }
        for (final entry in draft.items.entries) {
          await into(reminderExercises).insert(
            ReminderExercisesCompanion.insert(
              reminderId: reminderId,
              exerciseId: entry.key,
              target: entry.value,
            ),
          );
        }
        return reminderId;
      });

  Future<void> setReminderEnabled(int id, bool enabled) =>
      (update(reminders)..where((r) => r.id.equals(id)))
          .write(RemindersCompanion(enabled: Value(enabled)));

  Future<void> deleteReminder(int id) =>
      (delete(reminders)..where((r) => r.id.equals(id))).go();
}
