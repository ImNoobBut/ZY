import 'alarm_ringtone_picker.dart';

class StubAlarmRingtonePicker implements AlarmRingtonePicker {
  @override
  bool get isSupported => false;

  @override
  Future<String?> pickRingtone({String? currentUri}) async => null;
}

AlarmRingtonePicker createAlarmRingtonePicker() => StubAlarmRingtonePicker();
