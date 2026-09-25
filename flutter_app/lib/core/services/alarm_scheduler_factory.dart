import 'alarm_scheduler.dart';
import 'alarm_scheduler_stub.dart'
    if (dart.library.html) 'alarm_scheduler_web.dart'
    if (dart.library.io) 'alarm_scheduler_io.dart' as impl;

AlarmScheduler createPlatformAlarmScheduler() => impl.createAlarmScheduler();
