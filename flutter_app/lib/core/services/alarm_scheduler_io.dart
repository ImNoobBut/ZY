import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/models.dart';
import 'alarm_scheduler.dart';

/// Android (and iOS if ever used) wake scheduling via exact local notifications.
class MobileAlarmScheduler implements AlarmScheduler {
  MobileAlarmScheduler();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _permissionPermanentlyDenied = false;
  bool _exactAlarmDenied = false;

  static const _channelId = 'zy_wake_alarms_v2';
  static const _channelName = 'Wake alarms';

  @override
  bool get isBestEffortOnly => false;

  @override
  String get limitationCopy {
    if (Platform.isIOS) {
      return 'Wake alarms use local notifications when you grant permission. '
          'Allow alerts and sounds when iOS prompts you.';
    }
    return 'Wake alarms use exact local notifications when you grant permission. '
        'On Android 12+, also allow Alarms & reminders (exact alarms) in app settings.';
  }

  @override
  bool get permissionNeedsSystemSettings =>
      _permissionPermanentlyDenied || _exactAlarmDenied;

  @override
  String get permissionSettingsHint {
    if (Platform.isIOS) {
      return 'Notifications are blocked. Open iPhone Settings → Notifications → this app, '
          'then turn Allow Notifications on.';
    }
    if (_exactAlarmDenied) {
      return 'Alarms & reminders (exact alarms) are off. Open App info → Alarms & reminders '
          '(or Special app access → Alarms & reminders) and allow them, then Recheck.';
    }
    return 'Notifications are blocked. Open Android Settings → Apps → this app → Notifications, '
        'then allow them.';
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  @override
  Stream<SleepAlarm> get onAlarmFired => const Stream.empty();

  @override
  Future<void> dismissRinging() async {}

  @override
  Future<void> initialize() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Wake alarms for Sleeping Routine for Zy',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        // Alarm stream — more likely to alert even when phone is on vibrate.
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );
    _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    await initialize();
    if (kIsWeb) return false;

    var notificationsOk = true;
    var exactOk = true;
    if (Platform.isAndroid) {
      final notif = await Permission.notification.request();
      notificationsOk = notif.isGranted;
      _permissionPermanentlyDenied = notif.isPermanentlyDenied;

      // Plugin API opens the system exact-alarm screen on Android 12+.
      await _android?.requestExactAlarmsPermission();
      final canExact = await _android?.canScheduleExactNotifications();
      exactOk = canExact ?? true;
      _exactAlarmDenied = !exactOk;

      if (!exactOk) {
        // Fall back to opening app settings so user can enable Alarms & reminders.
        await openAppSettings();
      }
    } else if (Platform.isIOS) {
      final result = await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      notificationsOk = result ?? false;
      _permissionPermanentlyDenied = !notificationsOk;
    }
    return notificationsOk && exactOk;
  }

  @override
  Future<bool> hasPermission() async {
    if (kIsWeb) return false;
    if (Platform.isAndroid) {
      await initialize();
      final status = await Permission.notification.status;
      final canExact = await _android?.canScheduleExactNotifications();
      _permissionPermanentlyDenied = status.isPermanentlyDenied;
      _exactAlarmDenied = !(canExact ?? true);
      return status.isGranted && !_exactAlarmDenied;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    // iOS plugin does not expose a simple status API here; assume true after request.
    return ios != null;
  }

  @override
  Future<void> schedule(SleepAlarm alarm) async {
    await initialize();
    await cancel(alarm.id);
    if (!alarm.isEnabled) return;

    final hasPerm = await hasPermission();
    if (!hasPerm) {
      final granted = await requestPermission();
      if (!granted) {
        throw Exception(
          _exactAlarmDenied
              ? 'Alarms & reminders permission is required to schedule wake alarms.'
              : 'Notification permission is required to schedule alarms.',
        );
      }
    }

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Wake alarms for Sleeping Routine for Zy',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        playSound: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      ),
    );

    await _scheduleAlarmNotifications(alarm, details);
  }

  Future<void> _scheduleAlarmNotifications(
    SleepAlarm alarm,
    NotificationDetails details,
  ) async {
    if (alarm.repeatDays.isEmpty) {
      final next = alarm.nextFireAfter();
      final when = _toTz(next!);
      await _plugin.zonedSchedule(
        _notifId(alarm.id),
        alarm.label,
        'Time to wake up.',
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      return;
    }

    for (final weekday in alarm.repeatDays) {
      // Dart DateTime.weekday: Mon=1 … Sun=7 (matches SleepAlarm.repeatDays).
      final when = _nextInstanceOfWeekday(alarm.hour, alarm.minute, weekday);
      await _plugin.zonedSchedule(
        _notifId(alarm.id, weekday),
        alarm.label,
        'Time to wake up.',
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  @override
  Future<void> cancel(String alarmId) async {
    await initialize();
    await _plugin.cancel(_notifId(alarmId));
    for (var day = 1; day <= 7; day++) {
      await _plugin.cancel(_notifId(alarmId, day));
    }
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

  static const _bedtimeReminderId = 910001;
  static const _bedtimeChannelId = 'zy_bedtime_reminder';

  @override
  Future<void> scheduleBedtimeReminder({
    required int hour,
    required int minute,
    required bool enabled,
  }) async {
    await initialize();
    await cancelBedtimeReminder();
    if (!enabled) return;

    if (!await hasPermission()) {
      final granted = await requestPermission();
      if (!granted) return;
    }

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _bedtimeChannelId,
        'Bedtime reminder',
        description: 'Reminder to start your sleep routine',
        importance: Importance.defaultImportance,
      ),
    );

    final when = _nextInstance(hour, minute);
    await _plugin.zonedSchedule(
      _bedtimeReminderId,
      'Bedtime',
      'Time for your sleep routine',
      when,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _bedtimeChannelId,
          'Bedtime reminder',
          channelDescription: 'Reminder to start your sleep routine',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  @override
  Future<void> cancelBedtimeReminder() async {
    await initialize();
    await _plugin.cancel(_bedtimeReminderId);
  }

  tz.TZDateTime _nextInstance(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  tz.TZDateTime _toTz(DateTime local) =>
      tz.TZDateTime(tz.local, local.year, local.month, local.day, local.hour, local.minute);

  tz.TZDateTime _nextInstanceOfWeekday(int hour, int minute, int weekday) {
    var scheduled = _nextInstance(hour, minute);
    while (scheduled.weekday != weekday) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  int _notifId(String alarmId, [int weekday = 0]) =>
      Object.hash(alarmId, weekday) & 0x7FFFFFFF;
}

AlarmScheduler createAlarmScheduler() => MobileAlarmScheduler();
