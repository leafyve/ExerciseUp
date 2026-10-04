import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'exercise_icons.dart';

class ExercisesScreen extends ConsumerWidget {
  const ExercisesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercises = ref.watch(exercisesProvider).value ?? const <Exercise>[];
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Exercises')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('Custom exercise'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          for (final e in exercises)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.secondaryContainer,
                child: Icon(iconFor(e.icon),
                    color: theme.colorScheme.onSecondaryContainer),
              ),
              title: Text(e.name),
              subtitle: Text(
                'Default ${e.defaultAmount} ${e.unit.label}'
                '${e.dailyGoal > 0 ? ' · Goal ${e.dailyGoal}/day' : ' · No daily goal'}',
              ),
              trailing: e.isCustom
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Remove',
                      onPressed: () => _confirmRemove(context, ref, e),
                    )
                  : null,
              onTap: () => _edit(context, ref, e),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(
      BuildContext context, WidgetRef ref, Exercise e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${e.name}?'),
        content: const Text(
            'Your past logs are kept. Reminders that include it will no longer show it.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await ref.read(databaseProvider).archiveExercise(e.id);
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Exercise? e) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ExerciseSheet(existing: e),
    );
  }
}

class _ExerciseSheet extends ConsumerStatefulWidget {
  const _ExerciseSheet({this.existing});
  final Exercise? existing;

  @override
  ConsumerState<_ExerciseSheet> createState() => _ExerciseSheetState();
}

class _ExerciseSheetState extends ConsumerState<_ExerciseSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _amount = TextEditingController(
      text: '${widget.existing?.defaultAmount ?? 10}');
  late final _goal =
      TextEditingController(text: '${widget.existing?.dailyGoal ?? 0}');
  late ExerciseUnit _unit = widget.existing?.unit ?? ExerciseUnit.reps;
  late String _icon = widget.existing?.icon ?? 'fitness';

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _goal.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final db = ref.read(databaseProvider);
    final amount = (int.tryParse(_amount.text) ?? 10).clamp(1, 9999);
    final goal = (int.tryParse(_goal.text) ?? 0).clamp(0, 99999);
    if (_isNew) {
      final name = _name.text.trim();
      if (name.isEmpty) return;
      final id = await db.addExercise(
          name: name, unit: _unit, icon: _icon, defaultAmount: amount);
      if (goal > 0) await db.updateExercise(id, dailyGoal: goal);
    } else {
      await db.updateExercise(
        widget.existing!.id,
        name: widget.existing!.isCustom ? _name.text.trim() : null,
        defaultAmount: amount,
        dailyGoal: goal,
        icon: widget.existing!.isCustom ? _icon : null,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final canEditIdentity = _isNew || existing!.isCustom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isNew ? 'New exercise' : existing!.name,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (canEditIdentity) ...[
              TextField(
                controller: _name,
                autofocus: _isNew,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              if (_isNew)
                SegmentedButton<ExerciseUnit>(
                  segments: const [
                    ButtonSegment(
                        value: ExerciseUnit.reps, label: Text('Reps')),
                    ButtonSegment(
                        value: ExerciseUnit.seconds, label: Text('Seconds')),
                  ],
                  selected: {_unit},
                  onSelectionChanged: (s) => setState(() => _unit = s.first),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in exerciseIcons.entries)
                    ChoiceChip(
                      label: Icon(entry.value, size: 20),
                      selected: _icon == entry.key,
                      onSelected: (_) => setState(() => _icon = entry.key),
                      showCheckmark: false,
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: 'Default amount',
                        suffixText: _unit.label,
                        border: const OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _goal,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: 'Daily goal',
                        helperText: '0 = none',
                        suffixText: _unit.label,
                        border: const OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _save, child: const Text('Save')),
            ),
          ],
        ),
      ),
    );
  }
}
