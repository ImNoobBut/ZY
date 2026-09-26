import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../ui/widgets.dart';

class QuietSoundScreen extends StatelessWidget {
  const QuietSoundScreen({super.key});

  Future<void> _selectAndPreview(BuildContext context, QuietSound sound) async {
    final state = context.read<AppState>();
    await state.setQuietSound(sound);
    if (!context.mounted) return;
    final localRoutineActive = state.routineState == RoutineState.timerRunning &&
        state.activeRoutine?.musicSource == MusicSource.local;
    // Mid-routine setQuietSound already switches playback; preview would stop it.
    if (!localRoutineActive) {
      await state.previewQuietSound(sound);
    }
    if (!context.mounted) return;
    final err = state.errorMessage ?? state.audio.lastError;
    if (err != null && !state.audio.isPlaying) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err)),
      );
    }
  }

  Future<void> _previewOnly(BuildContext context, QuietSound sound) async {
    final state = context.read<AppState>();
    await state.previewQuietSound(sound);
    if (!context.mounted) return;
    final err = state.errorMessage ?? state.audio.lastError;
    if (err != null && !state.audio.isPlaying) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final selected = state.preferences.selectedQuietSound;

    return NightScaffold(
      title: 'Quiet sound',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Used when Spotify is not selected. Soft looping tones stay on-device.',
            style: TextStyle(color: AppTheme.secondaryText),
          ),
          const SizedBox(height: 16),
          for (final sound in QuietSound.values)
            ZyCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(sound.displayName),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selected == sound)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.check, color: AppTheme.accent),
                      ),
                    TextButton(
                      onPressed: () => _previewOnly(context, sound),
                      child: const Text('Preview'),
                    ),
                  ],
                ),
                onTap: () => _selectAndPreview(context, sound),
              ),
            ),
        ],
      ),
    );
  }
}
