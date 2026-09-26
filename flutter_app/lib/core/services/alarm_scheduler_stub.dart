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
  bool get permissionNeedsSystemSettings => false;

  @override
  String get permissionSettingsHint =>
      'Open system or browser settings and allow notifications for this app.';

  @override
  Stream<SleepAlarm> get onAlarmFired => const Stream.empty();

  @override
  Future<void> dismissRinging() async {}

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
    final keep = alarms.map((a) => a.id).toSet();
    for (final id in scheduled.map((a) => a.id).toList()) {
      if (!keep.contains(id)) {
        await cancel(id);
      }
    }
    for (final alarm in alarms) {
      if (alarm.isEnabled) {
        await schedule(alarm);
      } else {
        await cancel(alarm.id);
      }
    }
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
