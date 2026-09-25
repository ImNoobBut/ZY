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

  /// True when this platform can only remind while the page/app stays alive (web).
  bool get isBestEffortOnly;

  String get limitationCopy;
}
