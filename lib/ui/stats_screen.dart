import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../domain/progress.dart';
import '../providers.dart';
import 'exercise_icons.dart';

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  int? _exerciseId;
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exercises = ref.watch(exercisesProvider).value ?? const <Exercise>[];
    final logs = ref.watch(recentLogsProvider).value ?? const <LogEntry>[];
    final streak = ref.watch(streakProvider);

    if (exercises.isEmpty) return const SizedBox.shrink();
    final exercise = exercises.firstWhere(
      (e) => e.id == _exerciseId,
      orElse: () => exercises.first,
    );

    final records = [
      for (final l in logs)
        if (l.exerciseId == exercise.id) LogRecord(l.exerciseId, l.amount, l.loggedAt),
    ];
    final perDay = totalsByDay(records);
    final today = dayOf(DateTime.now());
    final series = [
      for (var i = _days - 1; i >= 0; i--)
        (
          day: DateTime(today.year, today.month, today.day - i),
          total: perDay[DateTime(today.year, today.month, today.day - i)]
                  ?[exercise.id] ??
              0,
        ),
    ];
    final windowTotal = series.fold<int>(0, (sum, p) => sum + p.total);
    final best = perDay.values
        .map((m) => m[exercise.id] ?? 0)
        .fold<int>(0, math.max);
    final unit = exercise.unit.label;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text('Progress', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
                child: _StatCard(
                    label: 'Current streak',
                    value: '${streak.current}',
                    suffix: streak.current == 1 ? 'day' : 'days',
                    icon: Icons.local_fire_department)),
            const SizedBox(width: 10),
            Expanded(
                child: _StatCard(
                    label: 'Longest streak',
                    value: '${streak.longest}',
                    suffix: streak.longest == 1 ? 'day' : 'days',
                    icon: Icons.emoji_events_outlined)),
          ],
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<int>(
          initialValue: exercise.id,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: [
            for (final e in exercises)
              DropdownMenuItem(
                value: e.id,
                child: Row(children: [
                  Icon(iconFor(e.icon), size: 20),
                  const SizedBox(width: 10),
                  Text(e.name),
                ]),
              ),
          ],
          onChanged: (v) => setState(() => _exerciseId = v),
        ),
        const SizedBox(height: 12),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 7, label: Text('7 days')),
            ButtonSegment(value: 30, label: Text('30 days')),
          ],
          selected: {_days},
          onSelectionChanged: (s) => setState(() => _days = s.first),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
                child: _StatCard(
                    label: 'Last $_days days',
                    value: '$windowTotal',
                    suffix: unit)),
            const SizedBox(width: 10),
            Expanded(
                child: _StatCard(
                    label: 'Best day', value: '$best', suffix: unit)),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: _DailyBars(series: series, goal: exercise.dailyGoal),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.suffix,
    this.icon,
  });

  final String label;
  final String value;
  final String suffix;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
            ]),
            const SizedBox(height: 6),
            Text.rich(TextSpan(children: [
              TextSpan(text: value, style: theme.textTheme.headlineSmall),
              TextSpan(
                  text: ' $suffix',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ])),
          ],
        ),
      ),
    );
  }
}

class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.series, required this.goal});
  final List<({DateTime day, int total})> series;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxTotal = series.map((p) => p.total).fold<int>(0, math.max);
    final top = math.max(math.max(maxTotal, goal), 1) * 1.15;
    final dense = series.length > 10;
    final labelEvery = dense ? 5 : 1;

    return BarChart(
      BarChartData(
        maxY: top,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (v, meta) => v == meta.max
                  ? const SizedBox.shrink()
                  : Text(meta.formattedValue,
                      style: theme.textTheme.labelSmall),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= series.length) return const SizedBox.shrink();
                // Always label the most recent bar; space the rest out.
                if ((series.length - 1 - i) % labelEvery != 0) {
                  return const SizedBox.shrink();
                }
                final d = series[i].day;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    dense ? DateFormat('d/M').format(d) : DateFormat('E').format(d),
                    style: theme.textTheme.labelSmall,
                  ),
                );
              },
            ),
          ),
        ),
        extraLinesData: goal > 0
            ? ExtraLinesData(horizontalLines: [
                HorizontalLine(
                  y: goal.toDouble(),
                  color: theme.colorScheme.tertiary,
                  strokeWidth: 1.5,
                  dashArray: [6, 4],
                ),
              ])
            : null,
        barGroups: [
          for (var i = 0; i < series.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: series[i].total.toDouble(),
                  width: dense ? 6 : 18,
                  borderRadius: BorderRadius.circular(4),
                  color: goal > 0 && series[i].total >= goal
                      ? theme.colorScheme.primary
                      : theme.colorScheme.primary.withValues(alpha: 0.55),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
