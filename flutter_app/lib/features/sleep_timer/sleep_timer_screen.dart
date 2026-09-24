import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../ui/widgets.dart';

class SleepTimerScreen extends StatelessWidget {
  const SleepTimerScreen({super.key});

  static const presets = [15, 30, 45, 60, 90];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final current = state.preferences.defaultSleepTimerSeconds ~/ 60;

    return NightScaffold(
      title: 'Sleep timer',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Music stops after this duration when you start tonight’s routine.',
            style: TextStyle(color: AppTheme.secondaryText),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in presets)
                ChoiceChip(
                  label: Text('$m min'),
                  selected: current == m,
                  onSelected: (_) => state.setDefaultTimerMinutes(m),
                ),
            ],
          ),
          const SizedBox(height: 24),
          ZyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Custom: $current min'),
                Slider(
                  value: current.toDouble().clamp(1, 180),
                  min: 1,
                  max: 180,
                  divisions: 179,
                  onChanged: (v) => state.setDefaultTimerMinutes(v.round()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
