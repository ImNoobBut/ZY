import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/greeting.dart';
import '../../ui/widgets.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const presets = [15, 30, 45, 60, 90];

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
    final bedtime = state.preferences.preferredBedtimeLabel;
    final reminder =
        state.preferences.bedtimeReminderEnabled ? 'Reminder on' : 'Reminder off';
    final streak = state.currentStreak;
    final currentMinutes = state.preferences.defaultSleepTimerSeconds ~/ 60;
    final preferSpotify = state.spotify.isAuthenticated &&
        state.preferences.selectedSpotifyUri != null;
    final activeSource = state.activeRoutine?.musicSource;
    final musicIsSpotify = active
        ? activeSource == MusicSource.spotify
        : preferSpotify;
    final musicLabel = active
        ? state.musicLabel
        : (preferSpotify
            ? (state.preferences.selectedSpotifyTitle ?? 'Spotify')
            : state.preferences.selectedQuietSound.displayName);
    final headline = active
        ? 'Sleep routine active'
        : greetingFor(DateTime.now(), state.preferences.displayName);

    return NightScaffold(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            headline,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            streak > 0 ? '$streak-night streak' : 'Start tonight’s streak',
            style: const TextStyle(color: AppTheme.secondaryText),
          ),
          if (!active) ...[
            const SizedBox(height: 4),
            const Text('Tonight', style: TextStyle(color: AppTheme.tertiaryText)),
          ],
          const SizedBox(height: 20),
          ZyCard(
            child: Column(
              children: [
                InkWell(
                  onTap: () {
                    if (musicIsSpotify) {
                      Navigator.of(context).pushNamed('/spotify');
                    } else {
                      Navigator.of(context).pushNamed('/quiet-sound');
                    }
                  },
                  child: _row('Music', musicLabel),
                ),
                _row(
                  active ? 'Music stops in' : 'Sleep timer',
                  active
                      ? _fmt(remaining)
                      : '$currentMinutes min',
                ),
                if (active && state.fadeStarted && state.audio.isFading)
                  _row('Audio', 'Fading out…'),
                _row('Bedtime', '$bedtime · $reminder'),
                _row('Alarm', alarmText),
              ],
            ),
          ),
          if (!active) ...[
            const SizedBox(height: 20),
            const Text(
              'Timer length',
              style: TextStyle(color: AppTheme.secondaryText),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in presets)
                  ChoiceChip(
                    label: Text('$m min'),
                    selected: currentMinutes == m,
                    onSelected: (_) => state.setDefaultTimerMinutes(m),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ZyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Custom: $currentMinutes min'),
                  Slider(
                    value: currentMinutes.toDouble().clamp(1, 180),
                    min: 1,
                    max: 180,
                    divisions: 179,
                    onChanged: (v) => state.setDefaultTimerMinutes(v.round()),
                  ),
                ],
              ),
            ),
          ],
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
          if (!preferSpotify) ...[
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Choose Spotify music',
              onPressed: () => Navigator.of(context).pushNamed('/spotify'),
            ),
          ],
          if (state.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(state.errorMessage!, style: const TextStyle(color: AppTheme.destructive)),
          ],
          if (state.infoMessage != null) ...[
            const SizedBox(height: 12),
            Text(state.infoMessage!, style: const TextStyle(color: AppTheme.secondaryText)),
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
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
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
