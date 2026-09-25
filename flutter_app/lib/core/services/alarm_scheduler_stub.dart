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

  bool bedtimeReminderScheduled = false;

  @override
  Future<void> scheduleBedtimeReminder({
    required int hour,
    required int minute,
    required bool enabled,
  }) async {
    bedtimeReminderScheduled = enabled;
  }

  @override
  Future<void> cancelBedtimeReminder() async {
    bedtimeReminderScheduled = false;
  }
}

AlarmScheduler createAlarmScheduler() => StubAlarmScheduler();
