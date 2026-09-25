import '../models/models.dart';
import 'alarm_scheduler.dart';

/// Fallback when neither dart:io nor dart:html is available (tests).
class StubAlarmScheduler implements AlarmScheduler {
  final List<SleepAlarm> scheduled = [];

  @override
  bool get isBestEffortOnly => true;

  @override
  String get limitationCopy => 'Alarms are not scheduled in this environment.';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> schedule(SleepAlarm alarm) async {
    scheduled.removeWhere((a) => a.id == alarm.id);
    if (alarm.isEnabled) scheduled.add(alarm);
  }

  @override
  Future<void> cancel(String alarmId) async {
    scheduled.removeWhere((a) => a.id == alarmId);
  }

  @override
  Future<void> reconcile(List<SleepAlarm> alarms) async {
    scheduled
      ..clear()
      ..addAll(alarms.where((a) => a.isEnabled));
  }
}

AlarmScheduler createAlarmScheduler() => StubAlarmScheduler();
