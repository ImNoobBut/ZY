import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../ui/widgets.dart';

class BedtimeSettingsScreen extends StatelessWidget {
  const BedtimeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final prefs = state.preferences;
    final bedtime = TimeOfDay(
      hour: prefs.preferredBedtimeHour,
      minute: prefs.preferredBedtimeMinute,
    );
    final wake = TimeOfDay(
      hour: prefs.preferredWakeHour,
      minute: prefs.preferredWakeMinute,
    );

    return NightScaffold(
      title: 'Bedtime',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ZyCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Preferred bedtime'),
                  trailing: Text(prefs.preferredBedtimeLabel),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: bedtime,
                    );
                    if (picked == null) return;
                    await state.updateBedtimePrefs(
                      bedtimeHour: picked.hour,
                      bedtimeMinute: picked.minute,
                    );
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Bedtime reminder'),
                  subtitle: Text(
                    state.alarmScheduler.isBestEffortOnly
                        ? 'Fires at bedtime while this tab stays open on web'
                        : 'Daily notification: “Time for your sleep routine”',
                    style: const TextStyle(color: AppTheme.secondaryText, fontSize: 13),
                  ),
                  value: prefs.bedtimeReminderEnabled,
                  onChanged: (v) => state.updateBedtimePrefs(bedtimeReminderEnabled: v),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Preferred wake'),
                  trailing: Text(
                    '${prefs.preferredWakeHour.toString().padLeft(2, '0')}:'
                    '${prefs.preferredWakeMinute.toString().padLeft(2, '0')}',
                  ),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: wake,
                    );
                    if (picked == null) return;
                    await state.updateBedtimePrefs(
                      wakeHour: picked.hour,
                      wakeMinute: picked.minute,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
