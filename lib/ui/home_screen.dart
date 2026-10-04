import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../domain/progress.dart';
import '../providers.dart';
import 'exercise_icons.dart';

/// "Today", "Yesterday", or "Sat, 3 Oct" (with the year if not this year).
String dayTitle(DateTime day, DateTime now) {
  final today = dayOf(now);
  final diff = today.difference(dayOf(day)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat(day.year == today.year ? 'EEE, d MMM' : 'EEE, d MMM y')
      .format(day);
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercises = ref.watch(exercisesProvider).value ?? const <Exercise>[];
    final day = ref.watch(viewedDayProvider);
    final totals = ref.watch(viewedTotalsProvider);
    final logs = ref.watch(viewedDayLogsProvider).value ?? const <LogEntry>[];
    final streak = ref.watch(streakProvider);
    final byId = {for (final e in exercises) e.id: e};
    final theme = Theme.of(context);
    final now = DateTime.now();
    final isToday = dayOf(day) == dayOf(now);

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 24),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous day',
              icon: const Icon(Icons.chevron_left),
              onPressed: dayOf(day).isAfter(earliestLoggableDay(now))
                  ? ref.read(selectedDayProvider.notifier).previous
                  : null,
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _pickDay(context, ref, day),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dayTitle(day, now),
                          style: theme.textTheme.headlineMedium),
                      Text(DateFormat('EEEE, d MMMM y').format(day),
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next day',
              icon: const Icon(Icons.chevron_right),
              onPressed: isToday
                  ? null
                  : ref.read(selectedDayProvider.notifier).next,
            ),
            _StreakBadge(days: streak.current),
          ],
        ),
        if (!isToday)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: const Icon(Icons.today, size: 18),
                label: const Text('Back to today'),
                onPressed: ref.read(selectedDayProvider.notifier).backToToday,
              ),
            ),
          ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Column(
            children: [
              for (final e in exercises)
                _ExerciseTile(
                  exercise: e,
                  day: day,
                  done: totals[e.id] ?? 0,
                  isToday: isToday,
                ),
              if (logs.isNotEmpty) ...[
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    isToday ? 'Logged today' : 'Logged ${dayTitle(day, now)}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 8),
                for (final l in logs)
                  if (byId[l.exerciseId] != null)
                    _LogRow(log: l, exercise: byId[l.exerciseId]!),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickDay(BuildContext context, WidgetRef ref, DateTime day) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: day,
      firstDate: earliestLoggableDay(now),
      lastDate: dayOf(now),
      helpText: 'Go to day',
    );
    if (picked != null) ref.read(selectedDayProvider.notifier).select(picked);
  }
}

class _StreakBadge extends StatelessWidget {
  const _StreakBadge({required this.days});
  final int days;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: days > 0 ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department,
              size: 20,
              color: days > 0 ? scheme.primary : scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text('$days', style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _ExerciseTile extends ConsumerWidget {
  const _ExerciseTile({
    required this.exercise,
    required this.day,
    required this.done,
    required this.isToday,
  });

  final Exercise exercise;
  final DateTime day;
  final int done;
  final bool isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final goal = exercise.dailyGoal;
    final unit = exercise.unit.label;
    final progress = goal > 0 ? (done / goal).clamp(0.0, 1.0) : null;
    final reached = goal > 0 && done >= goal;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showLogDialog(context, ref, exercise, day),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                height: 52,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress ?? 0,
                      strokeWidth: 5,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                    Icon(
                      reached ? Icons.check : iconFor(exercise.icon),
                      color: reached
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(exercise.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      goal > 0
                          ? '$done / $goal $unit'
                          : '$done $unit${isToday ? ' today' : ''}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => ref.read(databaseProvider).logExercise(
                      exercise.id,
                      exercise.defaultAmount,
                      at: logTimestampFor(day, DateTime.now()),
                    ),
                icon: const Icon(Icons.add, size: 18),
                label: Text('${exercise.defaultAmount}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogRow extends ConsumerWidget {
  const _LogRow({required this.log, required this.exercise});
  final LogEntry log;
  final Exercise exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey('log-${log.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Theme.of(context).colorScheme.errorContainer,
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) => ref.read(databaseProvider).deleteLog(log.id),
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(iconFor(exercise.icon), size: 20),
        title: Text('${log.amount} ${exercise.unit.label} ${exercise.name}'),
        trailing: Text(DateFormat.jm().format(log.loggedAt)),
      ),
    );
  }
}

/// Asks how much was done on [day] and logs it.
Future<void> showLogDialog(
  BuildContext context,
  WidgetRef ref,
  Exercise exercise,
  DateTime day,
) async {
  final now = DateTime.now();
  final controller = TextEditingController(text: '${exercise.defaultAmount}');
  final amount = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Log ${exercise.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dayTitle(day, now),
              style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                  color: Theme.of(ctx).colorScheme.primary)),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(suffixText: exercise.unit.label),
            onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v)),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text)),
          child: const Text('Log'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (amount != null && amount > 0) {
    await ref
        .read(databaseProvider)
        .logExercise(exercise.id, amount, at: logTimestampFor(day, now));
  }
}
