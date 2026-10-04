import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../domain/describe.dart';
import '../providers.dart';
import '../services/notification_service.dart';
import 'reminder_editor.dart';

class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders =
        ref.watch(remindersProvider).value ?? const <ReminderWithExercises>[];
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(context, null),
        icon: const Icon(Icons.add_alarm),
        label: const Text('New reminder'),
      ),
      body: reminders.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_none,
                        size: 56, color: theme.colorScheme.outline),
                    const SizedBox(height: 12),
                    Text('No reminders yet',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Create one to get nudged to move, e.g. 10 push-ups every 2 hours.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                for (final r in reminders)
                  _ReminderCard(
                    reminder: r,
                    onTap: () => _open(context, r),
                  ),
              ],
            ),
    );
  }

  void _open(BuildContext context, ReminderWithExercises? r) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ReminderEditor(existing: r)),
    );
  }
}

class _ReminderCard extends ConsumerWidget {
  const _ReminderCard({required this.reminder, required this.onTap});
  final ReminderWithExercises reminder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final r = reminder.reminder;
    final muted = theme.colorScheme.onSurfaceVariant;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              Expanded(
                child: Opacity(
                  opacity: r.enabled ? 1 : 0.5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.name, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(describeSchedule(reminder.schedule),
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: muted)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final i in reminder.items)
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                  '${i.target} ${i.exercise.unit.label} ${i.exercise.name}'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Column(
                children: [
                  Switch(
                    value: r.enabled,
                    onChanged: (v) async {
                      final db = ref.read(databaseProvider);
                      await db.setReminderEnabled(r.id, v);
                      await NotificationService.instance.rescheduleAll(db);
                    },
                  ),
                  IconButton(
                    tooltip: 'Send a test notification now',
                    icon: const Icon(Icons.notification_add_outlined),
                    onPressed: () => NotificationService.instance
                        .showNow(reminder),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
