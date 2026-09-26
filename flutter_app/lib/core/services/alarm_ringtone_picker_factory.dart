import 'alarm_ringtone_picker.dart';
import 'alarm_ringtone_picker_stub.dart'
    if (dart.library.html) 'alarm_ringtone_picker_web.dart'
    if (dart.library.io) 'alarm_ringtone_picker_io.dart' as impl;

AlarmRingtonePicker createAlarmRingtonePicker() =>
    impl.createAlarmRingtonePicker();
