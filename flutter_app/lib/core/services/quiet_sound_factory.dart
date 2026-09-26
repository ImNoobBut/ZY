import 'dart:math';
import 'dart:typed_data';

import '../models/models.dart';
import 'alarm_sound_factory.dart';

/// Procedural short looping WAV samples (parity with Swift SleepAudioSampleFactory).
class QuietSoundFactory {
  static Uint8List makeWav(QuietSound sound) {
    switch (sound) {
      case QuietSound.softTone:
        return _tone(frequency: 174, amplitude: 0.08);
      case QuietSound.deepHum:
        return _tone(frequency: 110, amplitude: 0.07);
      case QuietSound.whiteNoise:
        return _noise(filtered: false, amplitude: 0.05);
      case QuietSound.rain:
        return _noise(filtered: true, amplitude: 0.06);
    }
  }

  /// Louder looping beep for wake alarms (web in-tab ring).
  /// Prefer [AlarmSoundFactory.makeWav] for catalog sounds.
  static Uint8List makeAlarmWav() =>
      AlarmSoundFactory.makeWav(AlarmSound.systemDefault);

  static Uint8List _tone({
    required double frequency,
    required double amplitude,
    double durationSeconds = 2.0,
    double sampleRate = 22050,
  }) {
    final frameCount = (durationSeconds * sampleRate).round();
    final samples = Int16List(frameCount);
    final fadeFrames = (sampleRate * 0.15).round();
    for (var frame = 0; frame < frameCount; frame++) {
      final t = frame / sampleRate;
      final fadeIn = frame < fadeFrames ? frame / fadeFrames : 1.0;
      final fadeOut = frame > frameCount - fadeFrames
          ? (frameCount - frame) / fadeFrames
          : 1.0;
      final sample =
          sin(2 * pi * frequency * t) * amplitude * fadeIn * fadeOut;
      samples[frame] = (sample.clamp(-1.0, 1.0) * 32767).round();
    }
    return _wrapPcm(samples, sampleRate);
  }

  static Uint8List _noise({
    required bool filtered,
    required double amplitude,
    double durationSeconds = 2.0,
    double sampleRate = 22050,
  }) {
    final frameCount = (durationSeconds * sampleRate).round();
    final samples = Int16List(frameCount);
    final rng = Random(42);
    final fadeFrames = (sampleRate * 0.15).round();
    var prev = 0.0;
    for (var frame = 0; frame < frameCount; frame++) {
      var n = (rng.nextDouble() * 2 - 1);
      if (filtered) {
        // Simple low-pass for a gentler “rain-like” texture.
        n = prev * 0.85 + n * 0.15;
        prev = n;
      }
      final fadeIn = frame < fadeFrames ? frame / fadeFrames : 1.0;
      final fadeOut = frame > frameCount - fadeFrames
          ? (frameCount - frame) / fadeFrames
          : 1.0;
      final sample = n * amplitude * fadeIn * fadeOut;
      samples[frame] = (sample.clamp(-1.0, 1.0) * 32767).round();
    }
    return _wrapPcm(samples, sampleRate);
  }

  static Uint8List _wrapPcm(Int16List samples, double sampleRate) {
    final dataSize = samples.length * 2;
    final buffer = ByteData(44 + dataSize);
    void writeString(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        buffer.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    writeString(0, 'RIFF');
    buffer.setUint32(4, 36 + dataSize, Endian.little);
    writeString(8, 'WAVE');
    writeString(12, 'fmt ');
    buffer.setUint32(16, 16, Endian.little);
    buffer.setUint16(20, 1, Endian.little);
    buffer.setUint16(22, 1, Endian.little);
    buffer.setUint32(24, sampleRate.round(), Endian.little);
    buffer.setUint32(28, sampleRate.round() * 2, Endian.little);
    buffer.setUint16(32, 2, Endian.little);
    buffer.setUint16(34, 16, Endian.little);
    writeString(36, 'data');
    buffer.setUint32(40, dataSize, Endian.little);
    var offset = 44;
    for (final s in samples) {
      buffer.setInt16(offset, s, Endian.little);
      offset += 2;
    }
    return buffer.buffer.asUint8List();
  }
}
