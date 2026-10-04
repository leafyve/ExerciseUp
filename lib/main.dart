import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import 'data/database.dart';
import 'providers.dart';
import 'services/background_topup.dart';
import 'services/notification_service.dart';
import 'services/widget_sync.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = AppDatabase();
  final notifications = NotificationService.instance;
  await notifications.init();
  notifications.foregroundDb = db;
  WidgetSync.install();
  await HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);
  await registerReminderTopUp();

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const ExerciseUpApp(),
    ),
  );
}
