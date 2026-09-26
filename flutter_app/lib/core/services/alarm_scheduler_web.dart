import 'dart:async';
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_util' as js_util;
import 'dart:typed_data';

import '../debug/agent_debug_log.dart';
import '../models/models.dart';
import 'alarm_scheduler.dart';
import 'quiet_sound_factory.dart';

/// Best-effort browser reminders while the tab stays open.
///
/// Important for phones: never call [Notification.requestPermission] from
/// bootstrap/reconcile — mobile Chrome permanently denies prompts that are not
/// tied to a user gesture, which previously blocked all timer arming.
class WebAlarmScheduler implements AlarmScheduler {
  final Map<String, Timer> _timers = {};
  final Map<String, SleepAlarm> _armed = {};
  bool _permissionGranted = false;
  bool _audioUnlocked = false;
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
  String get limitationCopy =>
      'On phone browsers, keep this tab open (and preferably the screen on) so reminders can ring. '
      'Notifications help if the tab is in the background briefly. '
      'For a reliable wake alarm that works with the phone locked, install the Android or iPhone app.';

  @override
  bool get permissionNeedsSystemSettings =>
      html.Notification.supported && html.Notification.permission == 'denied';

  @override
  String get permissionSettingsHint =>
      'Notifications are blocked for this site. In Chrome: tap the lock (or tune) icon by the URL → '
      'Permissions → Notifications → Allow, then tap Allow alarms again.';

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
    // #region agent log
    agentDebugLog(
      hypothesisId: 'A',
      location: 'alarm_scheduler_web.dart:initialize',
      message: 'web alarm init',
      data: {
        'permission': html.Notification.supported
            ? html.Notification.permission
            : 'unsupported',
        'supported': html.Notification.supported,
        'secureContext': html.window.isSecureContext,
        'visibility': html.document.visibilityState,
      },
      runId: 'phone-fix',
    );
    // Debug-only: arm fire path in N seconds from the console / CDP.
    js.context['__agentArmAlarmInSeconds'] = (num seconds) {
      const id = '__agent_debug';
      _timers.remove(id)?.cancel();
      final alarm = SleepAlarm(
        id: id,
        hour: 0,
        minute: 0,
        label: 'Debug wake',
        isEnabled: true,
      );
      final delay = Duration(milliseconds: (seconds * 1000).round());
      agentDebugLog(
        hypothesisId: 'B',
        location: 'alarm_scheduler_web.dart:__agentArmAlarmInSeconds',
        message: 'debug timer armed',
        data: {
          'seconds': seconds,
          'delayMs': delay.inMilliseconds,
          'permission': html.Notification.permission,
          'audioUnlocked': _audioUnlocked,
        },
        runId: 'phone-fix',
      );
      _timers[id] = Timer(delay, () => _onFire(alarm, rearm: false));
      return true;
    };
    js.context['__agentUnlockAudio'] = () {
      unawaited(_unlockAudio());
      return _audioUnlocked;
    };
    // #endregion
  }

  void _syncPermissionFromBrowser() {
    _permissionGranted = html.Notification.supported &&
        html.Notification.permission == 'granted';
  }

  @override
  Future<bool> requestPermission() async {
    if (!html.Notification.supported) {
      // #region agent log
      agentDebugLog(
        hypothesisId: 'A',
        location: 'alarm_scheduler_web.dart:requestPermission',
        message: 'Notification API unsupported',
        data: {'supported': false},
        runId: 'phone-fix',
      );
      // #endregion
      return false;
    }
    // Already denied: browsers will not show a prompt; avoid a no-op call.
    if (html.Notification.permission == 'denied') {
      _permissionGranted = false;
      // #region agent log
      agentDebugLog(
        hypothesisId: 'A',
        location: 'alarm_scheduler_web.dart:requestPermission',
        message: 'permission already denied — needs site settings',
        data: {'result': 'denied', 'needsSettings': true},
        runId: 'phone-fix',
      );
      // #endregion
      return false;
    }
    final result = await html.Notification.requestPermission();
    _permissionGranted = result == 'granted';
    await _unlockAudio();
    // #region agent log
    agentDebugLog(
      hypothesisId: 'A',
      location: 'alarm_scheduler_web.dart:requestPermission',
      message: 'permission request result',
      data: {
        'result': result,
        'granted': _permissionGranted,
        'audioUnlocked': _audioUnlocked,
      },
      runId: 'phone-fix',
    );
    // #endregion
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
      // #region agent log
      agentDebugLog(
        hypothesisId: 'B',
        location: 'alarm_scheduler_web.dart:schedule',
        message: 'skip disabled alarm',
        data: {'alarmId': alarm.id},
        runId: 'phone-fix',
      );
      // #endregion
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
      // #region agent log
      agentDebugLog(
        hypothesisId: 'B',
        location: 'alarm_scheduler_web.dart:arm',
        message: 'nextFireAfter null',
        data: {
          'alarmId': current.id,
          'enabled': current.isEnabled,
          'repeatDays': current.repeatDays.toList(),
        },
        runId: 'phone-fix',
      );
      // #endregion
      return;
    }
    final delay = next.difference(DateTime.now());
    if (delay.isNegative) {
      // #region agent log
      agentDebugLog(
        hypothesisId: 'B',
        location: 'alarm_scheduler_web.dart:arm',
        message: 'negative delay skipped',
        data: {
          'alarmId': current.id,
          'next': next.toIso8601String(),
          'delayMs': delay.inMilliseconds,
        },
        runId: 'phone-fix',
      );
      // #endregion
      return;
    }

    // #region agent log
    agentDebugLog(
      hypothesisId: 'B',
      location: 'alarm_scheduler_web.dart:arm',
      message: 'timer armed',
      data: {
        'alarmId': current.id,
        'label': current.label,
        'hour': current.hour,
        'minute': current.minute,
        'repeatDays': current.repeatDays.toList(),
        'next': next.toIso8601String(),
        'delayMs': delay.inMilliseconds,
        'permission': html.Notification.supported
            ? html.Notification.permission
            : 'unsupported',
        'activeTimers': _timers.length,
        'audioUnlocked': _audioUnlocked,
        'notifOptional': true,
      },
      runId: 'phone-fix',
    );
    // #endregion

    _timers[current.id] = Timer(delay, () {
      _onFire(current, rearm: true);
    });
  }

  Future<void> _onBecameVisible() async {
    _syncPermissionFromBrowser();
    // Re-arm after mobile Chrome freezes background timers.
    for (final alarm in _armed.values.toList()) {
      if (alarm.isEnabled) {
        _arm(alarm);
      }
    }
    await _updateWakeLock();
    // #region agent log
    agentDebugLog(
      hypothesisId: 'E',
      location: 'alarm_scheduler_web.dart:_onBecameVisible',
      message: 're-armed after visibility',
      data: {
        'armed': _armed.length,
        'timers': _timers.length,
        'permission': html.Notification.supported
            ? html.Notification.permission
            : 'unsupported',
      },
      runId: 'phone-fix',
    );
    // #endregion
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
      _audioUnlocked = true;
    } catch (_) {
      _audioUnlocked = false;
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
    final visibility = html.document.visibilityState;
    var notifOk = false;
    String? notifError;

    _syncPermissionFromBrowser();
    if (_permissionGranted) {
      try {
        html.Notification(
          current.label,
          body: 'Time to wake up. (Web reminder — keep this tab open on phones)',
        );
        notifOk = true;
      } catch (e) {
        notifError = '$e';
      }
    }

    // Fire-and-await ring so logs reflect real play/overlay outcome.
    () async {
      var soundPlayed = false;
      String? soundError;
      var overlayShown = false;
      try {
        await _startRinging(current.label);
        soundPlayed = _ringPlayer != null;
        overlayShown = _overlay != null;
      } catch (e) {
        soundError = '$e';
        overlayShown = _overlay != null;
      }

      if (!_firedController.isClosed) {
        _firedController.add(current);
      }

      // #region agent log
      agentDebugLog(
        hypothesisId: 'C',
        location: 'alarm_scheduler_web.dart:Timer.fire',
        message: 'alarm timer fired',
        data: {
          'alarmId': current.id,
          'label': current.label,
          'notifOk': notifOk,
          'notifError': notifError,
          'permission': html.Notification.supported
              ? html.Notification.permission
              : 'unsupported',
          'visibility': visibility,
          'soundPlayed': soundPlayed,
          'soundError': soundError,
          'overlayShown': overlayShown,
          'audioUnlocked': _audioUnlocked,
          'hasSoundPath': true,
        },
        runId: 'phone-fix',
      );
      // #endregion
    }();

    if (rearm && current.repeatDays.isNotEmpty && current.isEnabled) {
      _arm(current);
    } else if (rearm && current.repeatDays.isEmpty) {
      // Once alarm: drop from armed set after fire.
      _armed.remove(current.id);
      unawaited(_updateWakeLock());
    }
  }

  Future<void> _startRinging(String label) async {
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
      ..text = label
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

    final wav = QuietSoundFactory.makeAlarmWav();
    final player = _audioFromWav(wav)
      ..loop = true
      ..volume = 1.0;
    _ringPlayer = player;
    try {
      await player.play();
    } catch (e) {
      // Autoplay may still block after long idle; overlay remains the fallback.
      // #region agent log
      agentDebugLog(
        hypothesisId: 'D',
        location: 'alarm_scheduler_web.dart:_startRinging',
        message: 'audio play rejected',
        data: {'error': '$e', 'audioUnlocked': _audioUnlocked},
        runId: 'phone-fix',
      );
      // #endregion
      rethrow;
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
    // #region agent log
    agentDebugLog(
      hypothesisId: 'E',
      location: 'alarm_scheduler_web.dart:reconcile',
      message: 'reconcile start',
      data: {
        'count': alarms.length,
        'enabled': alarms.where((a) => a.isEnabled).length,
        'priorTimers': _timers.keys.toList(),
        'permission': html.Notification.supported
            ? html.Notification.permission
            : 'unsupported',
      },
      runId: 'phone-fix',
    );
    // #endregion
    final keep = alarms.map((a) => a.id).toSet();
    for (final id in _timers.keys.toList()) {
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

AlarmScheduler createAlarmScheduler() => WebAlarmScheduler();
