import 'dart:async';
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_util' as js_util;
import 'dart:typed_data';

import '../models/models.dart';
import 'alarm_scheduler.dart';
import 'alarm_sound_factory.dart';
import 'quiet_sound_factory.dart';

/// Best-effort browser reminders while the tab stays open.
///
/// Important for phones: never call [Notification.requestPermission] from
/// bootstrap/reconcile — mobile Chrome permanently denies prompts that are not
/// tied to a user gesture, which previously blocked all timer arming.
class WebAlarmScheduler implements AlarmScheduler {
  final Map<String, Timer> _timers = {};
  final Map<String, SleepAlarm> _armed = {};
  final Set<String> _catchUpFired = {};
  bool _permissionGranted = false;
  html.AudioElement? _ringPlayer;
  html.Element? _overlay;
  StreamSubscription<html.Event>? _visibilitySub;
  Object? _wakeLock;
  final StreamController<SleepAlarm> _firedController =
      StreamController<SleepAlarm>.broadcast();

  @override
  Stream<SleepAlarm> get onAlarmFired => _firedController.stream;

  @override
  bool get isBestEffortOnly => true;

  @override
  String get limitationCopy {
    final kind = _phoneBrowserKind;
    if (kind == _PhoneBrowserKind.ios) {
      return 'On iPhone Safari, keep this tab open (screen on) so reminders can ring. '
          'Safari site notifications are limited — Add to Home Screen helps a bit. '
          'For a reliable wake alarm with the phone locked, use the iPhone app.';
    }
    if (kind == _PhoneBrowserKind.android) {
      return 'On Android Chrome, keep this tab open (screen on) so reminders can ring. '
          'Notifications help briefly in the background. '
          'For a reliable wake alarm with the phone locked, use the Android app.';
    }
    return 'On web, keep this tab open so reminders can ring. '
        'For a reliable wake alarm with the phone locked, use the Android or iPhone app.';
  }

  @override
  bool get permissionNeedsSystemSettings =>
      html.Notification.supported && html.Notification.permission == 'denied';

  @override
  String get permissionSettingsHint {
    switch (_phoneBrowserKind) {
      case _PhoneBrowserKind.ios:
        return 'Safari blocked or limits notifications for this site. '
            'In-tab ringing still works while this tab stays open. '
            'Optional: Share → Add to Home Screen, then allow notifications for the icon. '
            'For lock-screen wake alarms, use the iPhone app.';
      case _PhoneBrowserKind.android:
        return 'Chrome blocked notifications for this site. '
            'In-tab ringing still works while this tab stays open. '
            'Optional: tap the lock icon by the URL → Permissions → Notifications → Allow, '
            'then Recheck on the Alarms tab.';
      case _PhoneBrowserKind.other:
        return 'Notifications are blocked for this site. '
            'In-tab ringing still works while this tab stays open. '
            'Optional: allow notifications in browser site settings, then Recheck on Alarms.';
    }
  }

  _PhoneBrowserKind get _phoneBrowserKind {
    final ua = html.window.navigator.userAgent.toLowerCase();
    if (ua.contains('iphone') ||
        ua.contains('ipad') ||
        ua.contains('ipod') ||
        (ua.contains('mac') && ua.contains('mobile'))) {
      return _PhoneBrowserKind.ios;
    }
    if (ua.contains('android')) return _PhoneBrowserKind.android;
    return _PhoneBrowserKind.other;
  }
  @override
  Future<void> initialize() async {
    _syncPermissionFromBrowser();
    _visibilitySub?.cancel();
    _visibilitySub = html.document.onVisibilityChange.listen((_) {
      if (html.document.visibilityState == 'visible') {
        unawaited(_onBecameVisible());
      } else {
        unawaited(_releaseWakeLock());
      }
    });
  }

  void _syncPermissionFromBrowser() {
    _permissionGranted = html.Notification.supported &&
        html.Notification.permission == 'granted';
  }

  @override
  Future<bool> requestPermission() async {
    if (!html.Notification.supported) {
      return false;
    }
    // Already denied: browsers will not show a prompt; avoid a no-op call.
    if (html.Notification.permission == 'denied') {
      _permissionGranted = false;
      return false;
    }
    final result = await html.Notification.requestPermission();
    _permissionGranted = result == 'granted';
    await _unlockAudio();
    return _permissionGranted;
  }

  @override
  Future<bool> hasPermission() async {
    _syncPermissionFromBrowser();
    return _permissionGranted;
  }

  @override
  Future<void> schedule(SleepAlarm alarm) async {
    await cancel(alarm.id);
    if (!alarm.isEnabled) {
      _armed.remove(alarm.id);
      await _updateWakeLock();
      return;
    }

    // Refresh grant flag only — never prompt here (phone Chrome auto-denies).
    _syncPermissionFromBrowser();

    // Saving / toggling is a user gesture — unlock autoplay for later ring.
    await _unlockAudio();

    _armed[alarm.id] = alarm;
    _arm(alarm);
    await _updateWakeLock();
  }

  void _arm(SleepAlarm current) {
    _timers.remove(current.id)?.cancel();
    final next = current.nextFireAfter();
    if (next == null) {
      return;
    }
    final delay = next.difference(DateTime.now());
    if (delay.isNegative) {
      return;
    }

    _timers[current.id] = Timer(delay, () {
      _onFire(current, rearm: true);
    });
  }

  Future<void> _onBecameVisible() async {
    _syncPermissionFromBrowser();
    // Re-arm after mobile Chrome freezes background timers.
    // Also catch up if we missed a fire while the tab was frozen/backgrounded.
    for (final alarm in _armed.values.toList()) {
      if (!alarm.isEnabled) continue;
      final missed = _missedSlotWithinGrace(alarm);
      if (missed != null) {
        _onFire(alarm, rearm: true);
      } else {
        _arm(alarm);
      }
    }
    await _updateWakeLock();
  }

  /// If the alarm's intended slot was within [grace] in the past, return that slot.
  /// Mobile Chrome often kills timers in background — without catch-up the UI jumps
  /// to "Next: tomorrow" and the user hears nothing.
  DateTime? _missedSlotWithinGrace(
    SleepAlarm alarm, {
    Duration grace = const Duration(minutes: 30),
  }) {
    final now = DateTime.now();
    var slot = DateTime(now.year, now.month, now.day, alarm.hour, alarm.minute);
    if (alarm.repeatDays.isNotEmpty && !alarm.repeatDays.contains(slot.weekday)) {
      return null;
    }
    final ago = now.difference(slot);
    if (!ago.isNegative && ago <= grace) {
      final key = '${alarm.id}|${slot.toIso8601String()}';
      if (_catchUpFired.contains(key)) return null;
      _catchUpFired.add(key);
      return slot;
    }
    return null;
  }

  Future<void> _updateWakeLock() async {
    if (_armed.values.any((a) => a.isEnabled) &&
        html.document.visibilityState == 'visible') {
      await _acquireWakeLock();
    } else {
      await _releaseWakeLock();
    }
  }

  Future<void> _acquireWakeLock() async {
    try {
      final nav = js.context['navigator'];
      if (nav == null) return;
      final wakeLockApi = nav['wakeLock'];
      if (wakeLockApi == null) return;
      final sent = js_util.callMethod(wakeLockApi, 'request', ['screen']);
      _wakeLock = await js_util.promiseToFuture(sent);
    } catch (_) {
      _wakeLock = null;
    }
  }

  Future<void> _releaseWakeLock() async {
    final lock = _wakeLock;
    _wakeLock = null;
    if (lock == null) return;
    try {
      js_util.callMethod(lock, 'release', []);
    } catch (_) {}
  }

  Future<void> _unlockAudio() async {
    try {
      final silent = QuietSoundFactory.makeWav(QuietSound.softTone);
      final player = _audioFromWav(silent)
        ..loop = false
        ..volume = 0.01;
      await player.play();
      player.pause();
      player.currentTime = 0;
    } catch (_) {
      // Autoplay unlock is best-effort until a later user gesture.
    }
  }

  html.AudioElement _audioFromWav(Uint8List bytes) {
    final blob = html.Blob([bytes], 'audio/wav');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final audio = html.AudioElement()
      ..src = url
      ..preload = 'auto';
    return audio;
  }

  void _onFire(
    SleepAlarm current, {
    required bool rearm,
  }) {
    _syncPermissionFromBrowser();
    if (_permissionGranted) {
      try {
        html.Notification(
          current.label,
          body: 'Time to wake up. (Web reminder — keep this tab open on phones)',
        );
      } catch (_) {
        // Notification may fail; in-page ring/overlay is the reliable path.
      }
    }

    () async {
      try {
        await _startRinging(current);
      } catch (_) {
        // Overlay may still be visible as fallback.
      }

      if (!_firedController.isClosed) {
        _firedController.add(current);
      }
    }();

    if (rearm && current.repeatDays.isNotEmpty && current.isEnabled) {
      _arm(current);
    } else if (rearm && current.repeatDays.isEmpty) {
      // Once alarm: drop from armed set after fire.
      _armed.remove(current.id);
      unawaited(_updateWakeLock());
    }
  }

  Future<void> _startRinging(SleepAlarm alarm) async {
    await dismissRinging();

    final overlay = html.DivElement()
      ..id = 'zy-alarm-overlay'
      ..style.cssText = '''
        position:fixed;inset:0;z-index:2147483647;
        display:flex;align-items:center;justify-content:center;
        background:rgba(8,12,24,0.92);color:#f4f7ff;
        font-family:Segoe UI,system-ui,sans-serif;text-align:center;
      ''';
    final card = html.DivElement()..style.cssText = 'max-width:420px;padding:28px;';
    card.append(html.HeadingElement.h1()
      ..text = alarm.label
      ..style.cssText = 'margin:0 0 8px;font-size:28px;');
    card.append(html.ParagraphElement()
      ..text = 'Alarm is ringing. Dismiss to stop the sound.'
      ..style.cssText = 'margin:0 0 20px;opacity:0.85;');
    final button = html.ButtonElement()
      ..text = 'Dismiss alarm'
      ..style.cssText = '''
        padding:12px 22px;border:0;border-radius:10px;cursor:pointer;
        background:#6ea8ff;color:#081018;font-weight:600;font-size:16px;
      ''';
    button.onClick.listen((_) {
      unawaited(dismissRinging());
    });
    card.append(button);
    overlay.append(card);
    html.document.body?.append(overlay);
    _overlay = overlay;

    final wav = AlarmSoundFactory.makeWav(alarm.sound);
    final player = _audioFromWav(wav)
      ..loop = true
      ..volume = AlarmSoundFactory.maxVolume;
    _ringPlayer = player;
    try {
      await player.play();
    } catch (_) {
      // Autoplay may still block after long idle; overlay remains the fallback.
    }
  }

  @override
  Future<void> dismissRinging() async {
    _ringPlayer?.pause();
    _ringPlayer?.src = '';
    _ringPlayer = null;
    _overlay?.remove();
    _overlay = null;
  }

  @override
  Future<void> cancel(String alarmId) async {
    _timers.remove(alarmId)?.cancel();
    _armed.remove(alarmId);
  }

  @override
  Future<void> reconcile(List<SleepAlarm> alarms) async {
    final keep = alarms.map((a) => a.id).toSet();
    for (final id in _timers.keys.toList()) {
      if (!keep.contains(id)) {
        await cancel(id);
      }
    }
    for (final alarm in alarms) {
      if (alarm.isEnabled) {
        final missed = _missedSlotWithinGrace(alarm);
        if (missed != null) {
          _armed[alarm.id] = alarm;
          _onFire(alarm, rearm: true);
        } else {
          await schedule(alarm);
        }
      } else {
        await cancel(alarm.id);
      }
    }
    await _updateWakeLock();
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

    _syncPermissionFromBrowser();

    void arm() {
      final now = DateTime.now();
      var next = DateTime(now.year, now.month, now.day, hour, minute);
      if (!next.isAfter(now)) {
        next = next.add(const Duration(days: 1));
      }
      _bedtimeTimer = Timer(next.difference(now), () {
        _syncPermissionFromBrowser();
        if (_permissionGranted) {
          try {
            html.Notification(
              'Bedtime',
              body: 'Time for your sleep routine (keep this tab open on web)',
            );
          } catch (_) {}
        }
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

enum _PhoneBrowserKind { android, ios, other }

AlarmScheduler createAlarmScheduler() => WebAlarmScheduler();
