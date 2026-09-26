import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../app_state.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../ui/widgets.dart';

class AlarmsScreen extends StatelessWidget {
  const AlarmsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return NightScaffold(
      title: 'Alarms',
      actions: [
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: () => _openEditor(context, state, null),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            state.alarmScheduler.limitationCopy,
            style: const TextStyle(color: AppTheme.secondaryText),
          ),
          const SizedBox(height: 16),
          if (state.alarmsPermissionGranted != true) ...[
            ZyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.alarmScheduler.permissionNeedsSystemSettings
                        ? 'Notifications blocked'
                        : (state.alarmScheduler.isBestEffortOnly
                            ? 'Browser notifications off'
                            : 'Alarm permission is off'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.alarmScheduler.permissionNeedsSystemSettings
                        ? state.alarmScheduler.permissionSettingsHint
                        : (state.alarmScheduler.isBestEffortOnly
                            ? 'Optional on phone browsers: allow notifications for banners. '
                                'In-tab sound still works while this tab stays open on Android Chrome and iPhone Safari. '
                                'Tap Allow alarms to try.'
                            : 'Enable notifications (and exact alarms on Android) so wake alarms can ring.'),
                    style: const TextStyle(color: AppTheme.secondaryText),
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: state.alarmScheduler.permissionNeedsSystemSettings
                        ? 'Recheck permission'
                        : 'Allow alarms',
                    onPressed: () => state.requestAlarmPermission(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (state.errorMessage != null &&
              (state.errorMessage!.toLowerCase().contains('alarm') ||
                  state.errorMessage!.toLowerCase().contains('notification'))) ...[
            Text(state.errorMessage!, style: const TextStyle(color: AppTheme.destructive)),
            const SizedBox(height: 12),
          ],
          if (state.alarms.isEmpty)
            const ZyCard(child: Text('No alarms yet. Tap + to add one and choose which weekdays are On.'))
          else
            ...state.alarms.map((SleepAlarm alarm) {
              final next = alarm.nextFireAfter();
              final nextText = next == null
                  ? 'Off'
                  : 'Next: ${DateFormat('EEE, MMM d · HH:mm').format(next)}';
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ZyCard(
                  child: InkWell(
                    onTap: () => _openEditor(context, state, alarm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${alarm.hour.toString().padLeft(2, '0')}:${alarm.minute.toString().padLeft(2, '0')}',
                                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                                  ),
                                  Text(alarm.label, style: const TextStyle(color: AppTheme.secondaryText)),
                                  Text(alarm.repeatSummary, style: const TextStyle(color: AppTheme.tertiaryText)),
                                  Text(nextText, style: const TextStyle(color: AppTheme.accentSoft, fontSize: 13)),
                                ],
                              ),
                            ),
                            Switch(
                              value: alarm.isEnabled,
                              onChanged: (v) async {
                                final updated = state.alarms
                                    .map((a) => a.id == alarm.id ? a.copyWith(isEnabled: v) : a)
                                    .toList();
                                await state.saveAlarms(updated);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppTheme.destructive),
                              onPressed: () async {
                                await state.saveAlarms(
                                  state.alarms.where((a) => a.id != alarm.id).toList(),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _WeekdayChips(
                          selected: alarm.repeatDays,
                          onToggle: (day) async {
                            final days = Set<int>.from(alarm.repeatDays);
                            if (days.contains(day)) {
                              days.remove(day);
                            } else {
                              days.add(day);
                            }
                            final updated = state.alarms
                                .map((a) => a.id == alarm.id ? a.copyWith(repeatDays: days) : a)
                                .toList();
                            await state.saveAlarms(updated);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, AppState state, SleepAlarm? existing) async {
    final result = await showModalBottomSheet<SleepAlarm>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.sheet,
      barrierColor: AppTheme.sheetBarrier,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AlarmEditorSheet(initial: existing),
    );
    if (result == null) return;
    if (existing == null) {
      await state.saveAlarms([...state.alarms, result]);
    } else {
      await state.saveAlarms(
        state.alarms.map((a) => a.id == result.id ? result : a).toList(),
      );
    }
  }
}

class _WeekdayChips extends StatelessWidget {
  const _WeekdayChips({required this.selected, required this.onToggle});

  final Set<int> selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var day = 1; day <= 7; day++)
          FilterChip(
            label: Text(SleepAlarm.weekdayLabels[day - 1]),
            selected: selected.contains(day),
            onSelected: (_) => onToggle(day),
            selectedColor: AppTheme.accent.withValues(alpha: 0.35),
            checkmarkColor: AppTheme.primaryText,
            labelStyle: TextStyle(
              color: selected.contains(day) ? AppTheme.primaryText : AppTheme.secondaryText,
              fontSize: 12,
            ),
          ),
      ],
    );
  }
}

class _AlarmEditorSheet extends StatefulWidget {
  const _AlarmEditorSheet({this.initial});

  final SleepAlarm? initial;

  @override
  State<_AlarmEditorSheet> createState() => _AlarmEditorSheetState();
}

class _AlarmEditorSheetState extends State<_AlarmEditorSheet> {
  late TimeOfDay _time;
  late Set<int> _days;
  late TextEditingController _label;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _time = TimeOfDay(hour: initial?.hour ?? 7, minute: initial?.minute ?? 0);
    // New alarms default to "once" so a near-future test fires today (not only Mon–Fri).
    _days = Set<int>.from(initial?.repeatDays ?? <int>{});
    _label = TextEditingController(text: initial?.label ?? 'Wake up');
    _enabled = initial?.isEnabled ?? true;
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = SleepAlarm(
      id: widget.initial?.id ?? 'preview',
      hour: _time.hour,
      minute: _time.minute,
      isEnabled: _enabled,
      repeatDays: _days,
    ).nextFireAfter();

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.initial == null ? 'Add alarm' : 'Edit alarm',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Time'),
            trailing: Text(
              _time.format(context),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            onTap: () async {
              final picked = await showTimePicker(context: context, initialTime: _time);
              if (picked != null) setState(() => _time = picked);
            },
          ),
          TextField(
            controller: _label,
            decoration: const InputDecoration(labelText: 'Label', filled: true),
          ),
          const SizedBox(height: 16),
          const Text('Repeat (tap days that are On)', style: TextStyle(color: AppTheme.tertiaryText)),
          const SizedBox(height: 8),
          _WeekdayChips(
            selected: _days,
            onToggle: (day) {
              setState(() {
                if (_days.contains(day)) {
                  _days.remove(day);
                } else {
                  _days.add(day);
                }
              });
            },
          ),
          const SizedBox(height: 8),
          Text(
            _days.isEmpty
                ? 'Once — fires at the next matching time.'
                : 'Repeats: ${SleepAlarm(id: 'x', hour: 0, minute: 0, repeatDays: _days).repeatSummary}',
            style: const TextStyle(color: AppTheme.secondaryText, fontSize: 13),
          ),
          if (preview != null)
            Text(
              'Next fire: ${DateFormat('EEE, MMM d · HH:mm').format(preview)}',
              style: const TextStyle(color: AppTheme.accentSoft, fontSize: 13),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enabled'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          const SizedBox(height: 8),
          PrimaryButton(
            label: 'Save alarm',
            onPressed: () {
              Navigator.of(context).pop(
                SleepAlarm(
                  id: widget.initial?.id ?? const Uuid().v4(),
                  hour: _time.hour,
                  minute: _time.minute,
                  label: _label.text.trim().isEmpty ? 'Wake up' : _label.text.trim(),
                  isEnabled: _enabled,
                  repeatDays: Set<int>.from(_days),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
