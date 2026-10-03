import 'package:flutter/foundation.dart';
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
      page = 1;
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
              label: page == 2 ? 'Start' : 'Continue',
              onPressed: () async {
                if (page < 2) {
                  setState(() => page++);
                  return;
                }
                await state.completeOnboarding(timerMinutes: timerMinutes);
              },
            ),
            if (page == 1) ...[
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
          'A simple Spotify sleep timer.',
          'Connect Spotify, set a timer, and playback pauses when time is up.',
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _text(
              'Connect Spotify',
              'Premium and an active Spotify device are needed for playback control.',
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
              if (kDebugMode) ...[
                const SizedBox(height: 8),
                SecondaryButton(
                  label: 'Demo connect (Windows testing)',
                  onPressed: () async {
                    await state.connectSpotifyDemo();
                  },
                ),
              ],
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
              'Default timer',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'You can change this anytime on Home.',
              style: TextStyle(color: AppTheme.secondaryText),
            ),
            const SizedBox(height: 20),
            ZyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sleep timer length'),
                  Slider(
                    value: timerMinutes.toDouble(),
                    min: 5,
                    max: 120,
                    divisions: 23,
                    label: '$timerMinutes min',
                    onChanged: (v) => setState(() => timerMinutes = v.round()),
                  ),
                  Text('$timerMinutes minutes'),
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
