import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/database.dart';
import '../domain/messages.dart';
import '../domain/models.dart';
import '../domain/schedule.dart';
import 'widget_sync.dart';

const _actionDone = 'done';
const _actionSnooze = 'snooze';
const _actionSkip = 'skip';

/// Notification ids are `reminderId * _idStride + slot`. Slots below
/// [_snoozeSlot] are scheduled occurrences; [_snoozeSlot] is the one-off
/// snooze for that reminder.
const _idStride = 1000;
const _snoozeSlot = 999;

const _snoozeMinutes = 10;

/// Total scheduled notifications we allow ourselves. Android caps pending
/// alarms per app (around 500 on many devices).
const _globalBudget = 400;
const _maxPerReminder = 200;

/// Runs in a background isolate when the user taps an action button while
/// the app is not in the foreground.
@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse response) async {
  DartPluginRegistrant.ensureInitialized();
  final service = NotificationService.instance;
  await service.init();
  WidgetSync.install();
  final db = AppDatabase();
  try {
    await service.handleResponse(response, db);
  } finally {
    await db.close();
  }
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final ScheduleCalculator _calculator = const ScheduleCalculator();

  bool _initialised = false;

  /// Database used for foreground action taps. Set by the app on start.
  AppDatabase? foregroundDb;

  /// Called after an action changes data so the UI can refresh.
  VoidCallback? onDataChanged;

  Future<void> init() async {
    if (_initialised) return;
    tzdata.initializeTimeZones();
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_exerciseup'),
      ),
      onDidReceiveNotificationResponse: _onForegroundResponse,
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    // Android fixes sound/vibration per channel, so each combination the user
    // can pick in the reminder editor gets its own channel.
    for (final c in _channels) {
      await android?.createNotificationChannel(AndroidNotificationChannel(
        c.id,
        c.name,
        description: 'Exercise reminders',
        importance: c.silent ? Importance.defaultImportance : Importance.high,
        playSound: !c.silent,
        enableVibration: c.vibrate,
      ));
    }
    _initialised = true;
  }

  /// Asks for the runtime notification permission (Android 13+).
  /// Returns whether notifications can be shown.
  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    return await android.requestNotificationsPermission() ?? false;
  }

  Future<bool> notificationsEnabled() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? false;
  }

  Future<bool> canScheduleExact() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.canScheduleExactNotifications() ?? false;
  }

  /// Rebuilds every pending reminder notification from the database.
  /// Snoozes are left alone. Call on app start, after any reminder edit, and
  /// after notification actions.
  Future<void> rescheduleAll(AppDatabase db) async {
    await init();
    final reminders = await db.getReminders();
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      if (p.id % _idStride != _snoozeSlot) await _plugin.cancel(id: p.id);
    }

    final active = reminders.where((r) => r.reminder.enabled).toList();
    if (active.isEmpty) return;

    final exact = await canScheduleExact();
    final mode = exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
    final budget = (_globalBudget ~/ active.length).clamp(1, _maxPerReminder);
    final now = DateTime.now();

    for (final r in active) {
      if (r.items.isEmpty) continue;
      final times = _calculator.nextFireTimes(r.schedule, now, count: budget);
      for (var slot = 0; slot < times.length; slot++) {
        await _plugin.zonedSchedule(
          id: r.reminder.id * _idStride + slot,
          scheduledDate: tz.TZDateTime.from(times[slot], tz.local),
          notificationDetails: _details(r, seed: times[slot].millisecondsSinceEpoch ~/ 60000),
          androidScheduleMode: mode,
          title: r.reminder.name,
          body: _body(r),
          payload: '${r.reminder.id}',
        );
      }
    }
  }

  /// Shows a notification right now. Used by the "test reminder" button.
  Future<void> showNow(ReminderWithExercises r) async {
    await init();
    await _plugin.show(
      id: r.reminder.id * _idStride + _snoozeSlot - 1,
      title: r.reminder.name,
      body: _body(r),
      notificationDetails: _details(r, seed: DateTime.now().minute),
      payload: '${r.reminder.id}',
    );
  }

  Future<void> cancelAllForReminder(int reminderId) async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      if (p.id ~/ _idStride == reminderId) await _plugin.cancel(id: p.id);
    }
  }

  // ----------------------------------------------------------------- actions

  Future<void> _onForegroundResponse(NotificationResponse response) async {
    final db = foregroundDb;
    if (db == null) return;
    await handleResponse(response, db);
    onDataChanged?.call();
  }

  /// Applies a Done / Snooze / Skip tap. A plain tap on the body is ignored
  /// here; it just opens the app.
  Future<void> handleResponse(
    NotificationResponse response,
    AppDatabase db,
  ) async {
    final reminderId = int.tryParse(response.payload ?? '');
    if (reminderId == null) return;
    final reminder = await db.getReminder(reminderId);
    if (reminder == null) return;

    switch (response.actionId) {
      case _actionDone:
        final now = DateTime.now();
        for (final item in reminder.items) {
          await db.logExercise(item.exercise.id, item.target,
              reminderId: reminderId, at: now);
        }
      case _actionSnooze:
        await init();
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final exact = await android?.canScheduleExactNotifications() ?? false;
        await _plugin.zonedSchedule(
          id: reminderId * _idStride + _snoozeSlot,
          scheduledDate: tz.TZDateTime.now(tz.local)
              .add(const Duration(minutes: _snoozeMinutes)),
          notificationDetails: _details(reminder, seed: DateTime.now().minute),
          androidScheduleMode: exact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          title: reminder.reminder.name,
          body: _body(reminder),
          payload: '$reminderId',
        );
      case _actionSkip:
      default:
        break;
    }
  }

  // ----------------------------------------------------------------- content

  String _body(ReminderWithExercises r) {
    final what = r.items
        .map((i) => '${i.target} ${_unitText(i)} ${i.exercise.name}')
        .join(' · ');
    return what;
  }

  String _unitText(ReminderItem i) =>
      i.exercise.unit == ExerciseUnit.seconds ? 'sec' : '×';

  NotificationDetails _details(ReminderWithExercises r, {required int seed}) {
    final channel = _channelFor(r.reminder.sound, r.reminder.vibrate);
    final message = motivationalMessageFor(seed);
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: 'Exercise reminders',
        importance: channel.silent ? Importance.defaultImportance : Importance.high,
        priority: channel.silent ? Priority.defaultPriority : Priority.high,
        playSound: !channel.silent,
        enableVibration: channel.vibrate,
        category: AndroidNotificationCategory.reminder,
        styleInformation: BigTextStyleInformation('${_body(r)}\n$message'),
        actions: const [
          AndroidNotificationAction(_actionDone, 'Done'),
          AndroidNotificationAction(_actionSnooze, 'Snooze 10m'),
          AndroidNotificationAction(_actionSkip, 'Skip'),
        ],
      ),
    );
  }
}

class _Channel {
  const _Channel(this.id, this.name, {required this.silent, required this.vibrate});
  final String id;
  final String name;
  final bool silent;
  final bool vibrate;
}

const _channels = [
  _Channel('reminder_sound_vibrate', 'Sound + vibration', silent: false, vibrate: true),
  _Channel('reminder_sound', 'Sound only', silent: false, vibrate: false),
  _Channel('reminder_vibrate', 'Vibration only', silent: true, vibrate: true),
  _Channel('reminder_silent', 'Silent', silent: true, vibrate: false),
];

_Channel _channelFor(String sound, bool vibrate) {
  final silent = sound == 'silent';
  return _channels.firstWhere((c) => c.silent == silent && c.vibrate == vibrate);
}
