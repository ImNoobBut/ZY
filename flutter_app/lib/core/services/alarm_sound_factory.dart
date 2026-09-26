import 'dart:math';
import 'dart:typed_data';

import '../models/models.dart';

/// Procedural wake-alarm WAV samples (louder than quiet-routine tones).
class AlarmSoundFactory {
  /// Full app playback volume for wake preview / web ring.
  static const double maxVolume = 1.0;

  static Uint8List makeWav(AlarmSound sound) {
    switch (sound) {
      case AlarmSound.systemDefault:
        return _defaultChirp();
      case AlarmSound.gentle:
        return _gentlePulse();
      case AlarmSound.chime:
        return _chimeBell();
    }
  }

  /// Classic two-tone alarm chirp (two pulses per second).
  static Uint8List _defaultChirp() {
    const sampleRate = 22050.0;
    const durationSeconds = 1.0;
    final frameCount = (durationSeconds * sampleRate).round();
    final samples = Int16List(frameCount);
    for (var frame = 0; frame < frameCount; frame++) {
      final t = frame / sampleRate;
      final gate = (t % 0.5) < 0.28 ? 1.0 : 0.0;
      final sample =
          (sin(2 * pi * 880 * t) * 0.45 + sin(2 * pi * 1100 * t) * 0.25) * gate;
      samples[frame] = (sample.clamp(-1.0, 1.0) * 32767).round();
    }
    return _wrapPcm(samples, sampleRate);
  }

  /// Softer lower-frequency pulse for a gentler wake.
  static Uint8List _gentlePulse() {
    const sampleRate = 22050.0;
    const durationSeconds = 1.2;
    final frameCount = (durationSeconds * sampleRate).round();
    final samples = Int16List(frameCount);
    for (var frame = 0; frame < frameCount; frame++) {
      final t = frame / sampleRate;
      final gate = (t % 0.6) < 0.35 ? 1.0 : 0.0;
      final env = gate * sin(pi * ((t % 0.6) / 0.35).clamp(0.0, 1.0));
      final sample = sin(2 * pi * 440 * t) * 0.32 * env +
          sin(2 * pi * 550 * t) * 0.12 * env;
      samples[frame] = (sample.clamp(-1.0, 1.0) * 32767).round();
    }
    return _wrapPcm(samples, sampleRate);
  }

  /// Short two-note bell-like chime.
  static Uint8List _chimeBell() {
    const sampleRate = 22050.0;
    const durationSeconds = 1.4;
    final frameCount = (durationSeconds * sampleRate).round();
    final samples = Int16List(frameCount);
    for (var frame = 0; frame < frameCount; frame++) {
      final t = frame / sampleRate;
      double note(double start, double freq, double amp) {
        final local = t - start;
        if (local < 0 || local > 0.55) return 0.0;
        final decay = exp(-local * 4.5);
        return sin(2 * pi * freq * local) * amp * decay +
            sin(2 * pi * freq * 2 * local) * amp * 0.25 * decay;
      }

      final sample = note(0.05, 784, 0.4) + note(0.55, 988, 0.38);
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
