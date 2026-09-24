import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../ui/widgets.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final active = state.routineState == RoutineState.timerRunning;
    final remaining = state.remaining();
    final alarm = (() {
      for (final a in state.alarms) {
        if (a.isEnabled) return a;
      }
      return null;
    })();
    final alarmText = alarm == null
        ? 'None'
        : '${alarm.hour.toString().padLeft(2, '0')}:${alarm.minute.toString().padLeft(2, '0')}';

    return NightScaffold(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            active ? 'Sleep routine active' : 'Good evening, Zy',
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
          ),
          if (!active) ...[
            const SizedBox(height: 8),
            const Text('Tonight', style: TextStyle(color: AppTheme.tertiaryText)),
          ],
          const SizedBox(height: 20),
          ZyCard(
            child: Column(
              children: [
                _row('Music', state.musicLabel),
                _row(
                  active ? 'Music stops in' : 'Sleep timer',
                  active
                      ? _fmt(remaining)
                      : '${state.preferences.defaultSleepTimerSeconds ~/ 60} min',
                ),
                _row('Alarm', alarmText),
              ],
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: active ? 'End Routine' : 'Start Sleep Routine',
            busy: state.busy,
            onPressed: () async {
              if (active) {
                await state.endRoutine();
              } else {
                await state.startRoutine();
              }
            },
          ),
          if (state.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(state.errorMessage!, style: const TextStyle(color: AppTheme.destructive)),
          ],
          const SizedBox(height: 16),
          const Text(
            'The sleep timer uses saved start and end times, so it stays accurate after leaving the app.',
            style: TextStyle(color: AppTheme.tertiaryText, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _row(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Text(title, style: const TextStyle(color: AppTheme.secondaryText)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _fmt(Duration? d) {
    if (d == null) return '—';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }
}
