import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../domain/models.dart';
import '../domain/schedule.dart';
import '../providers.dart';
import '../services/notification_service.dart';
import 'exercise_icons.dart';

class ReminderEditor extends ConsumerStatefulWidget {
  const ReminderEditor({super.key, this.existing});
  final ReminderWithExercises? existing;

  @override
  ConsumerState<ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends ConsumerState<ReminderEditor> {
  late final TextEditingController _name;
  late final TextEditingController _intervalValue;
  late ReminderMode _mode;
  late bool _intervalInHours;
  late MinuteOfDay _windowStart;
  late MinuteOfDay _windowEnd;
  late Set<int> _weekdays;
  late List<MinuteOfDay> _fixedTimes;
  late String _sound;
  late bool _vibrate;

  /// exerciseId -> amount controller, present only for selected exercises.
  final Map<int, TextEditingController> _selected = {};
  bool _initialisedItems = false;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    final s = r?.schedule ??
        const ReminderSchedule(mode: ReminderMode.interval, intervalMinutes: 120);
    _name = TextEditingController(text: r?.reminder.name ?? 'Move break');
    _mode = s.mode;
    _intervalInHours = s.intervalMinutes % 60 == 0;
    _intervalValue = TextEditingController(
        text: '${_intervalInHours ? s.intervalMinutes ~/ 60 : s.intervalMinutes}');
    _windowStart = s.windowStart;
    _windowEnd = s.windowEnd;
    _weekdays = {...s.weekdays};
    _fixedTimes = [...s.fixedTimes];
    _sound = r?.reminder.sound ?? 'default';
    _vibrate = r?.reminder.vibrate ?? true;
    if (r != null) {
      for (final i in r.items) {
        _selected[i.exercise.id] = TextEditingController(text: '${i.target}');
      }
      _initialisedItems = true;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _intervalValue.dispose();
    for (final c in _selected.values) {
      c.dispose();
    }
    super.dispose();
  }

  int get _intervalMinutes {
    final v = int.tryParse(_intervalValue.text) ?? 0;
    return _intervalInHours ? v * 60 : v;
  }

  Future<MinuteOfDay?> _pickTime(MinuteOfDay initial) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _save() async {
    final name = _name.text.trim().isEmpty ? 'Move break' : _name.text.trim();
    if (_selected.isEmpty) return _snack('Pick at least one exercise.');
    if (_weekdays.isEmpty) return _snack('Pick at least one day.');
    if (_mode == ReminderMode.interval && _intervalMinutes < 1) {
      return _snack('Interval must be at least 1 minute.');
    }
    if (_mode == ReminderMode.fixedTimes && _fixedTimes.isEmpty) {
      return _snack('Add at least one time.');
    }

    final items = {
      for (final e in _selected.entries)
        e.key: (int.tryParse(e.value.text) ?? 1).clamp(1, 9999),
    };
    final draft = ReminderDraft(
      name: name,
      enabled: widget.existing?.reminder.enabled ?? true,
      sound: _sound,
      vibrate: _vibrate,
      items: items,
      schedule: ReminderSchedule(
        mode: _mode,
        intervalMinutes: _intervalMinutes.clamp(1, 24 * 60),
        windowStart: _windowStart,
        windowEnd: _windowEnd,
        weekdays: _weekdays,
        fixedTimes: _fixedTimes,
      ),
    );

    final db = ref.read(databaseProvider);
    await db.saveReminder(draft, id: widget.existing?.reminder.id);
    await NotificationService.instance.rescheduleAll(db);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this reminder?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final db = ref.read(databaseProvider);
    final id = widget.existing!.reminder.id;
    await NotificationService.instance.cancelAllForReminder(id);
    await db.deleteReminder(id);
    await NotificationService.instance.rescheduleAll(db);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exercises = ref.watch(exercisesProvider).value ?? const <Exercise>[];

    // New reminders start with push-ups selected so the form is never empty.
    if (!_initialisedItems && exercises.isNotEmpty) {
      final first = exercises.first;
      _selected[first.id] =
          TextEditingController(text: '${first.defaultAmount}');
      _initialisedItems = true;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New reminder' : 'Edit reminder'),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: _save, child: const Text('Save')),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Reminder name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          _SectionTitle('What to do'),
          for (final e in exercises) _exerciseRow(e),
          const SizedBox(height: 24),
          _SectionTitle('When'),
          SegmentedButton<ReminderMode>(
            segments: const [
              ButtonSegment(
                  value: ReminderMode.interval,
                  icon: Icon(Icons.repeat),
                  label: Text('Repeat every')),
              ButtonSegment(
                  value: ReminderMode.fixedTimes,
                  icon: Icon(Icons.schedule),
                  label: Text('At set times')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 16),
          if (_mode == ReminderMode.interval) ..._intervalSection(theme),
          if (_mode == ReminderMode.fixedTimes) ..._fixedTimesSection(),
          const SizedBox(height: 16),
          Text('On these days', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(weekdayShortNames[d - 1]),
                  selected: _weekdays.contains(d),
                  onSelected: (on) => setState(
                      () => on ? _weekdays.add(d) : _weekdays.remove(d)),
                ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionTitle('Alert'),
          DropdownButtonFormField<String>(
            initialValue: _sound,
            decoration: const InputDecoration(
                labelText: 'Sound', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'default', child: Text('Default')),
              DropdownMenuItem(value: 'silent', child: Text('Silent')),
            ],
            onChanged: (v) => setState(() => _sound = v ?? 'default'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Vibrate'),
            value: _vibrate,
            onChanged: (v) => setState(() => _vibrate = v),
          ),
        ],
      ),
    );
  }

  Widget _exerciseRow(Exercise e) {
    final on = _selected.containsKey(e.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              secondary: Icon(iconFor(e.icon)),
              title: Text(e.name),
              value: on,
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selected[e.id] =
                      TextEditingController(text: '${e.defaultAmount}');
                } else {
                  _selected.remove(e.id)?.dispose();
                }
              }),
            ),
          ),
          if (on)
            SizedBox(
              width: 96,
              child: TextField(
                controller: _selected[e.id],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  isDense: true,
                  suffixText: e.unit.label,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _intervalSection(ThemeData theme) => [
        Row(
          children: [
            SizedBox(
              width: 88,
              child: TextField(
                controller: _intervalValue,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                    labelText: 'Every', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('minutes')),
                ButtonSegment(value: true, label: Text('hours')),
              ],
              selected: {_intervalInHours},
              onSelectionChanged: (s) =>
                  setState(() => _intervalInHours = s.first),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Only between', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final t = await _pickTime(_windowStart);
                  if (t != null) setState(() => _windowStart = t);
                },
                child: Text(formatMinuteOfDay(_windowStart)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('and'),
            ),
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final t = await _pickTime(_windowEnd);
                  if (t != null) setState(() => _windowEnd = t);
                },
                child: Text(formatMinuteOfDay(_windowEnd)),
              ),
            ),
          ],
        ),
        if (_windowEnd <= _windowStart)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Runs past midnight into the next day.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
      ];

  List<Widget> _fixedTimesSection() => [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in ([..._fixedTimes]..sort()))
              InputChip(
                label: Text(formatMinuteOfDay(t)),
                onDeleted: () => setState(() => _fixedTimes.remove(t)),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Add time'),
              onPressed: () async {
                final t = await _pickTime(9 * 60);
                if (t != null && !_fixedTimes.contains(t)) {
                  setState(() => _fixedTimes.add(t));
                }
              },
            ),
          ],
        ),
      ];
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}
