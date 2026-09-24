import 'package:flutter/material.dart';
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
          onPressed: () async {
            final time = await showTimePicker(
              context: context,
              initialTime: const TimeOfDay(hour: 7, minute: 0),
            );
            if (time == null) return;
            final next = [
              ...state.alarms,
              SleepAlarm(
                id: const Uuid().v4(),
                hour: time.hour,
                minute: time.minute,
              ),
            ];
            await state.saveAlarms(next);
          },
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'On Android, alarms use local notifications when permitted. On web, treat these as in-app reminders only.',
            style: TextStyle(color: AppTheme.secondaryText),
          ),
          const SizedBox(height: 16),
          if (state.alarms.isEmpty)
            const ZyCard(child: Text('No alarms yet. Tap + to add one.'))
          else
            ...state.alarms.map((SleepAlarm alarm) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ZyCard(
                  child: Row(
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
                          ],
                        ),
                      ),
                      Switch(
                        value: alarm.isEnabled,
                        onChanged: (v) async {
                          alarm.isEnabled = v;
                          await state.saveAlarms([...state.alarms]);
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
                ),
              );
            }),
        ],
      ),
    );
  }
}
