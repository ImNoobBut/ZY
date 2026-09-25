import 'dart:async';
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import '../models/models.dart';
import 'alarm_scheduler.dart';

/// Best-effort browser reminders while the tab stays open.
class WebAlarmScheduler implements AlarmScheduler {
  final Map<String, Timer> _timers = {};
  bool _permissionGranted = false;

  @override
  bool get isBestEffortOnly => true;

  @override
  String get limitationCopy =>
      'On web, alarms only fire while this tab stays open (and notifications are allowed). '
      'They skip days that are not toggled On. For a real wake alarm, use Android or iPhone.';

  @override
  Future<void> initialize() async {
    _permissionGranted = html.Notification.permission == 'granted';
  }

  @override
  Future<bool> requestPermission() async {
    if (!html.Notification.supported) return false;
    final result = await html.Notification.requestPermission();
    _permissionGranted = result == 'granted';
    return _permissionGranted;
  }

  @override
  Future<bool> hasPermission() async {
    _permissionGranted = html.Notification.permission == 'granted';
    return _permissionGranted;
  }

  @override
  Future<void> schedule(SleepAlarm alarm) async {
    await cancel(alarm.id);
    if (!alarm.isEnabled) return;

    if (!_permissionGranted) {
      final ok = await requestPermission();
      if (!ok) {
        throw Exception('Browser notification permission is required for web alarms.');
      }
    }

    void arm(SleepAlarm current) {
      final next = current.nextFireAfter();
      if (next == null) return;
      final delay = next.difference(DateTime.now());
      if (delay.isNegative) return;

      _timers[current.id] = Timer(delay, () {
        try {
          html.Notification(
            current.label,
            body: 'Time to wake up. (Web reminder — tab must stay open)',
          );
        } catch (_) {
          // Some browsers block Notification construction even after grant.
        }
        // Re-arm repeating alarms only (once alarms stop after first fire).
        if (current.repeatDays.isNotEmpty && current.isEnabled) {
          arm(current);
        }
      });
    }

    arm(alarm);
  }

  @override
  Future<void> cancel(String alarmId) async {
    _timers.remove(alarmId)?.cancel();
  }

  @override
  Future<void> reconcile(List<SleepAlarm> alarms) async {
    for (final alarm in alarms) {
      if (alarm.isEnabled) {
        await schedule(alarm);
      } else {
        await cancel(alarm.id);
      }
    }
  }

  Timer? _bedtimeTimer;

  @override
  Future<void> scheduleBedtimeReminder({
    required int hour,
    required int minute,
    required bool enabled,
  }) async {
    await cancelBedtimeReminder();
    if (!enabled) return;

    if (!_permissionGranted) {
      final ok = await requestPermission();
      if (!ok) return;
    }

    void arm() {
      final now = DateTime.now();
      var next = DateTime(now.year, now.month, now.day, hour, minute);
      if (!next.isAfter(now)) {
        next = next.add(const Duration(days: 1));
      }
      _bedtimeTimer = Timer(next.difference(now), () {
        try {
          html.Notification(
            'Bedtime',
            body: 'Time for your sleep routine (keep this tab open on web)',
          );
        } catch (_) {}
        arm();
      });
    }

    arm();
  }

  @override
  Future<void> cancelBedtimeReminder() async {
    _bedtimeTimer?.cancel();
    _bedtimeTimer = null;
  }
}

AlarmScheduler createAlarmScheduler() => WebAlarmScheduler();
