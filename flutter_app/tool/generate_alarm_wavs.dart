// ignore_for_file: avoid_print
/// Writes catalog alarm WAVs into Flutter assets and Android res/raw.
///
/// Run from flutter_app/:
///   dart run tool/generate_alarm_wavs.dart
library;

import 'dart:io';

import 'package:sleeping_routine_for_zy/core/models/models.dart';
import 'package:sleeping_routine_for_zy/core/services/alarm_sound_factory.dart';

Future<void> main() async {
  final root = Directory.current;
  final assetsDir = Directory('${root.path}/assets/audio');
  final rawDir = Directory('${root.path}/android/app/src/main/res/raw');
  await assetsDir.create(recursive: true);
  await rawDir.create(recursive: true);

  for (final sound in AlarmSound.values) {
    final bytes = AlarmSoundFactory.makeWav(sound);
    final assetFile = File('${assetsDir.path}/${sound.resourceName}.wav');
    final rawFile = File('${rawDir.path}/${sound.resourceName}.wav');
    await assetFile.writeAsBytes(bytes, flush: true);
    await rawFile.writeAsBytes(bytes, flush: true);
    print('Wrote ${assetFile.path} (${bytes.length} bytes)');
    print('Wrote ${rawFile.path}');
  }
}
