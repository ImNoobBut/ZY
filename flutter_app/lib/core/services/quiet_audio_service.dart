import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'quiet_sound_factory.dart';

/// Loops a quiet app-owned tone. Does not control Spotify.
class QuietAudioService {
  final AudioPlayer _player = AudioPlayer();
  bool isPlaying = false;
  bool isFading = false;
  QuietSound _currentSound = QuietSound.softTone;
  Timer? _fadeTimer;
  double _volume = 0.35;

  Future<void> play([QuietSound sound = QuietSound.softTone]) async {
    await cancelFade();
    _currentSound = sound;
    _volume = 0.35;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(_volume);
      final bytes = QuietSoundFactory.makeWav(sound);
      await _player.play(BytesSource(bytes));
      isPlaying = true;
    } catch (e) {
      try {
        await _player.play(AssetSource('audio/quiet_night.wav'));
        isPlaying = true;
      } catch (_) {
        isPlaying = false;
        if (kDebugMode) {
          debugPrint('Quiet audio unavailable: $e');
        }
      }
    }
  }

  Future<void> preview(QuietSound sound) async {
    await play(sound);
    Timer(const Duration(seconds: 3), () {
      if (!isFading) {
        unawaited(stop());
      }
    });
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _player.setVolume(_volume);
  }

  /// Linear fade to silence over [duration], then stops.
  Future<void> fadeOut({Duration duration = const Duration(seconds: kFadeOutSeconds)}) async {
    if (!isPlaying || isFading) return;
    isFading = true;
    final steps = duration.inMilliseconds ~/ 250;
    final safeSteps = steps < 1 ? 1 : steps;
    final startVol = _volume;
    var step = 0;
    final completer = Completer<void>();
    _fadeTimer?.cancel();
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) async {
      step += 1;
      final t = (step / safeSteps).clamp(0.0, 1.0);
      await setVolume(startVol * (1.0 - t));
      if (step >= safeSteps) {
        timer.cancel();
        await stop();
        if (!completer.isCompleted) completer.complete();
      }
    });
    return completer.future;
  }

  Future<void> cancelFade() async {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    isFading = false;
  }

  Future<void> stop() async {
    await cancelFade();
    await _player.stop();
    isPlaying = false;
    _volume = 0.35;
  }

  Future<void> dispose() async {
    await cancelFade();
    await _player.dispose();
  }

  QuietSound get currentSound => _currentSound;
}
