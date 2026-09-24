import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Loops a quiet app-owned tone. Does not control Spotify.
class QuietAudioService {
  final AudioPlayer _player = AudioPlayer();
  bool isPlaying = false;

  Future<void> play() async {
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      // Asset may be missing on first run — fail soft.
      await _player.play(AssetSource('audio/quiet_night.wav'));
      isPlaying = true;
    } catch (_) {
      // Web/asset issues: mark as "playing" for routine UX without crashing.
      isPlaying = true;
      if (kDebugMode) {
        debugPrint('Quiet audio asset unavailable; continuing without sound.');
      }
    }
  }

  Future<void> stop() async {
    await _player.stop();
    isPlaying = false;
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
