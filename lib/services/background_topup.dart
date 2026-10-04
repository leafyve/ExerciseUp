import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../data/database.dart';
import 'notification_service.dart';
import 'widget_sync.dart';

const _topUpTask = 'exerciseup.topUp';
const _topUpUniqueName = 'exerciseup-topup';

/// How often the OS may run the refill. WorkManager treats this as a minimum
/// and may delay it in Doze, so scheduled batches must cover well beyond it.
const _topUpEvery = Duration(hours: 1);

/// Entry point for WorkManager's background isolate.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    if (task != _topUpTask) return true;

    WidgetSync.install();
    final db = AppDatabase();
    try {
      await NotificationService.instance.rescheduleAll(db);
      await WidgetSync.push(db); // also rolls the widget over at midnight
      return true;
    } catch (e, st) {
      debugPrint('Reminder top-up failed: $e\n$st');
      // Returning false asks WorkManager to retry with backoff.
      return false;
    } finally {
      await db.close();
    }
  });
}

/// Registers the recurring refill. Safe to call on every launch.
Future<void> registerReminderTopUp() async {
  await Workmanager().initialize(backgroundDispatcher);
  await Workmanager().registerPeriodicTask(
    _topUpUniqueName,
    _topUpTask,
    frequency: _topUpEvery,
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}
