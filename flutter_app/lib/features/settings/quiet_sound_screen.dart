import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../ui/widgets.dart';

class QuietSoundScreen extends StatelessWidget {
  const QuietSoundScreen({super.key});

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
                trailing: selected == sound
                    ? const Icon(Icons.check, color: AppTheme.accent)
                    : TextButton(
                        onPressed: () => state.previewQuietSound(sound),
                        child: const Text('Preview'),
                      ),
                onTap: () async {
                  await state.setQuietSound(sound);
                },
              ),
            ),
        ],
      ),
    );
  }
}
