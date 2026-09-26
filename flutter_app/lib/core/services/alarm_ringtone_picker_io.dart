import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'alarm_ringtone_picker.dart';

class IoAlarmRingtonePicker implements AlarmRingtonePicker {
  static const _channel = MethodChannel('zy.sleeping_routine/ringtone_picker');

  @override
  bool get isSupported => Platform.isAndroid;

  @override
  Future<String?> pickRingtone({String? currentUri}) async {
    if (!isSupported) return null;
    try {
      final result = await _channel.invokeMethod<String>(
        'pickRingtone',
        <String, dynamic>{'currentUri': currentUri},
      );
      final trimmed = result?.trim();
      if (trimmed == null || trimmed.isEmpty) return null;
      return trimmed;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

AlarmRingtonePicker createAlarmRingtonePicker() => IoAlarmRingtonePicker();
