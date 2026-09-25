import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../ui/widgets.dart';

class SleepHistoryScreen extends StatelessWidget {
  const SleepHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final sessions = state.sessions.take(14).toList();
    final dateFmt = DateFormat('EEE, MMM d · HH:mm');

    return NightScaffold(
      title: 'Sleep history',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ZyCard(
            child: Text(
              state.currentStreak > 0
                  ? 'Current streak: ${state.currentStreak} night${state.currentStreak == 1 ? '' : 's'}'
                  : 'No streak yet — start a routine tonight.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 16),
          if (sessions.isEmpty)
            const Text(
              'Completed routines will appear here.',
              style: TextStyle(color: AppTheme.secondaryText),
            )
          else
            for (final s in sessions)
              ZyCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateFmt.format(s.startedAt.toLocal()),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _durationLabel(s),
                      style: const TextStyle(color: AppTheme.secondaryText),
                    ),
                    if (s.notes != null && s.notes!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        s.notes!,
                        style: const TextStyle(color: AppTheme.tertiaryText, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
        ],
      ),
    );
  }

  String _durationLabel(SleepSessionRecord session) {
    final end = session.completedAt ?? session.musicStoppedAt;
    if (end == null) return 'Incomplete';
    final mins = end.difference(session.startedAt).inMinutes;
    if (mins < 1) return 'Under 1 min';
    return '$mins min';
  }
}
