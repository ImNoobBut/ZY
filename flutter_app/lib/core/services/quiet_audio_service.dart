import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'quiet_sound_factory.dart';

/// Loops a quiet app-owned tone. Does not control Spotify.
class QuietAudioService {
  static const double _baseVolume = 0.5;

  final AudioPlayer _player = AudioPlayer();
  bool isPlaying = false;
  bool isFading = false;
  QuietSound _currentSound = QuietSound.softTone;
  Timer? _fadeTimer;
  Timer? _previewTimer;
  double _volume = _baseVolume;
  String? lastError;

  Future<bool> play([QuietSound sound = QuietSound.softTone]) async {
    _cancelPreviewTimer();
    await cancelFade();
    try {
      await _player.stop();
    } catch (_) {}
    _currentSound = sound;
    _volume = _baseVolume;
    lastError = null;

    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(_volume);
      final bytes = QuietSoundFactory.makeWav(sound);
      await _player.play(BytesSource(bytes, mimeType: 'audio/wav'));
      isPlaying = true;
      return true;
    } catch (e) {
      // Retry once with a fresh buffer (helps flaky web BytesSource paths).
      try {
        await _player.setReleaseMode(ReleaseMode.loop);
        await _player.setVolume(_volume);
        final retryBytes = QuietSoundFactory.makeWav(sound);
        await _player.play(BytesSource(retryBytes, mimeType: 'audio/wav'));
        isPlaying = true;
        return true;
      } catch (retryError) {
        try {
          await _player.play(AssetSource('audio/quiet_night.wav'));
          isPlaying = true;
          lastError =
              'Could not play ${sound.displayName}; using fallback tone.\n$retryError';
          return true;
        } catch (assetError) {
          isPlaying = false;
          lastError = 'Quiet audio unavailable: $assetError';
          if (kDebugMode) {
            debugPrint('Quiet audio unavailable: $e / $retryError / $assetError');
          }
          return false;
        }
      }
    }
  }

  Future<bool> preview(QuietSound sound) async {
    final ok = await play(sound);
    if (!ok) return false;
    _cancelPreviewTimer();
    _previewTimer = Timer(const Duration(seconds: 3), () {
      if (!isFading) {
        unawaited(stop());
      }
    });
    return true;
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
    _cancelPreviewTimer();
    await cancelFade();
    await _player.stop();
    isPlaying = false;
    _volume = _baseVolume;
  }

  Future<void> dispose() async {
    _cancelPreviewTimer();
    await cancelFade();
    await _player.dispose();
  }

  void _cancelPreviewTimer() {
    _previewTimer?.cancel();
    _previewTimer = null;
  }

  QuietSound get currentSound => _currentSound;
}
