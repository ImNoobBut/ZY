import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../ui/widgets.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int page = 0;
  int timerMinutes = 30;
  bool alarmEnabled = true;
  TimeOfDay bedtime = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay wake = const TimeOfDay(hour: 7, minute: 0);
  bool _didApplyOauthLanding = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didApplyOauthLanding) return;
    _didApplyOauthLanding = true;
    final state = context.read<AppState>();
    // After Spotify redirects back, land on the music step so success/error is visible.
    if (state.spotify.isAuthenticated ||
        (state.infoMessage?.contains('Spotify') ?? false) ||
        (state.errorMessage?.toLowerCase().contains('spotify') ?? false)) {
      page = 2;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return NightScaffold(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _page(state)),
            const SizedBox(height: 16),
            PrimaryButton(
              label: page == 3 ? 'Start my routine' : 'Continue',
              onPressed: () async {
                if (page < 3) {
                  setState(() => page++);
                  return;
                }
                await state.completeOnboarding(
                  timerMinutes: timerMinutes,
                  alarmEnabled: alarmEnabled,
                  bedtimeHour: bedtime.hour,
                  bedtimeMinute: bedtime.minute,
                  wakeHour: wake.hour,
                  wakeMinute: wake.minute,
                );
              },
            ),
            if (page == 2) ...[
              const SizedBox(height: 8),
              SecondaryButton(
                label: 'Skip Spotify for now',
                onPressed: () => setState(() => page++),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _page(AppState state) {
    switch (page) {
      case 0:
        return _text(
          'Sleep better with a simple routine.',
          'Set your music, sleep timer, and alarm in one place.',
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _text(
              'Stay on schedule',
              state.alarmScheduler.isBestEffortOnly
                  ? 'On web, alarms are browser reminders while this tab stays open — not a phone alarm clock.'
                  : 'Allow notifications (and exact alarms on Android) so wake alarms can ring.',
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Allow alarms',
              onPressed: () async {
                await state.requestAlarmPermission();
                if (!mounted) return;
                final ok = state.alarmsPermissionGranted == true;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ok ? 'Alarm permission on.' : 'Permission denied — enable later on the Alarms tab or in Settings.')),
                );
              },
            ),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _text(
              'Music for bedtime',
              'Connect Spotify or use a quiet in-app tone. Playback needs Premium + an active Spotify device.',
            ),
            const SizedBox(height: 16),
            if (state.spotify.isAuthenticated) ...[
              ZyCard(
                child: Text(
                  state.infoMessage ?? 'Spotify connected. Continue when ready.',
                  style: const TextStyle(height: 1.4),
                ),
              ),
            ] else ...[
              PrimaryButton(
                label: 'Connect Spotify (browser)',
                onPressed: () async {
                  try {
                    await state.spotify.openAuthorizeInBrowser();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                    }
                  }
                },
              ),
              const SizedBox(height: 8),
              SecondaryButton(
                label: 'Demo connect (Windows testing)',
                onPressed: () async {
                  await state.connectSpotifyDemo();
                },
              ),
            ],
            if (state.errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(state.errorMessage!, style: const TextStyle(color: AppTheme.destructive)),
            ],
            if (!state.spotify.isAuthenticated && state.infoMessage != null) ...[
              const SizedBox(height: 12),
              Text(state.infoMessage!, style: const TextStyle(color: AppTheme.secondaryText)),
            ],
          ],
        );
      default:
        return ListView(
          children: [
            const Text(
              'Your routine',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose defaults you can change anytime.',
              style: TextStyle(color: AppTheme.secondaryText),
            ),
            const SizedBox(height: 20),
            ZyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Default sleep timer'),
                  Slider(
                    value: timerMinutes.toDouble(),
                    min: 5,
                    max: 120,
                    divisions: 23,
                    label: '$timerMinutes min',
                    onChanged: (v) => setState(() => timerMinutes = v.round()),
                  ),
                  Text('$timerMinutes minutes'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Default alarm'),
                    value: alarmEnabled,
                    onChanged: (v) => setState(() => alarmEnabled = v),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bedtime'),
                    trailing: Text(bedtime.format(context)),
                    onTap: () async {
                      final next = await showTimePicker(context: context, initialTime: bedtime);
                      if (next != null) setState(() => bedtime = next);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Wake time'),
                    trailing: Text(wake.format(context)),
                    onTap: () async {
                      final next = await showTimePicker(context: context, initialTime: wake);
                      if (next != null) setState(() => wake = next);
                    },
                  ),
                ],
              ),
            ),
          ],
        );
    }
  }

  Widget _text(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Text(subtitle, style: const TextStyle(color: AppTheme.secondaryText, height: 1.4)),
      ],
    );
  }
}
