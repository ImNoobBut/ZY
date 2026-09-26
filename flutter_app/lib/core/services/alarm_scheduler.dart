import '../models/models.dart';

/// Cross-platform alarm scheduling (Android exact notifications, web best-effort).
abstract class AlarmScheduler {
  Future<void> initialize();

  /// Requests notification / exact-alarm permission. Returns whether scheduling is allowed.
  Future<bool> requestPermission();

  Future<bool> hasPermission();

  Future<void> schedule(SleepAlarm alarm);

  Future<void> cancel(String alarmId);

  Future<void> reconcile(List<SleepAlarm> alarms);

  /// Daily bedtime reminder at hour:minute. Cancelled when [enabled] is false.
  Future<void> scheduleBedtimeReminder({
    required int hour,
    required int minute,
    required bool enabled,
  });

  Future<void> cancelBedtimeReminder();

  /// True when this platform can only remind while the page/app stays alive (web).
  bool get isBestEffortOnly;

  String get limitationCopy;

  /// Emits when a wake alarm rings while the app is alive (mainly web).
  Stream<SleepAlarm> get onAlarmFired => const Stream.empty();

  /// Stops in-tab alarm sound / overlay if ringing.
  Future<void> dismissRinging() async {}
}
