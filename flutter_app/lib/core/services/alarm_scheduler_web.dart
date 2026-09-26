import 'dart:async';
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:typed_data';

import '../debug/agent_debug_log.dart';
import '../models/models.dart';
import 'alarm_scheduler.dart';
import 'quiet_sound_factory.dart';

/// Best-effort browser reminders while the tab stays open.
class WebAlarmScheduler implements AlarmScheduler {
  final Map<String, Timer> _timers = {};
  bool _permissionGranted = false;
  bool _audioUnlocked = false;
  html.AudioElement? _ringPlayer;
  html.Element? _overlay;
  final StreamController<SleepAlarm> _firedController =
      StreamController<SleepAlarm>.broadcast();

  @override
  Stream<SleepAlarm> get onAlarmFired => _firedController.stream;

  @override
  bool get isBestEffortOnly => true;

  @override
  String get limitationCopy =>
      'On web, alarms only fire while this tab stays open (and notifications are allowed). '
      'They skip days that are not toggled On. For a real wake alarm, use Android or iPhone.';

  @override
  Future<void> initialize() async {
    _permissionGranted = html.Notification.permission == 'granted';
    // #region agent log
    agentDebugLog(
      hypothesisId: 'A',
      location: 'alarm_scheduler_web.dart:initialize',
      message: 'web alarm init',
      data: {
        'permission': html.Notification.permission,
        'supported': html.Notification.supported,
        'secureContext': html.window.isSecureContext,
        'visibility': html.document.visibilityState,
      },
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

  @override
  Future<bool> requestPermission() async {
    if (!html.Notification.supported) {
      // #region agent log
      agentDebugLog(
        hypothesisId: 'A',
        location: 'alarm_scheduler_web.dart:requestPermission',
        message: 'Notification API unsupported',
        data: {'supported': false},
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
    );
    // #endregion
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
    if (!alarm.isEnabled) {
      // #region agent log
      agentDebugLog(
        hypothesisId: 'B',
        location: 'alarm_scheduler_web.dart:schedule',
        message: 'skip disabled alarm',
        data: {'alarmId': alarm.id},
      );
      // #endregion
      return;
    }

    if (!_permissionGranted) {
      final ok = await requestPermission();
      if (!ok) {
        // #region agent log
        agentDebugLog(
          hypothesisId: 'A',
          location: 'alarm_scheduler_web.dart:schedule',
          message: 'schedule blocked: no permission',
          data: {'alarmId': alarm.id, 'permission': html.Notification.permission},
        );
        // #endregion
        throw Exception('Browser notification permission is required for web alarms.');
      }
    }

    // Saving an alarm is a user gesture — unlock autoplay for later ring.
    await _unlockAudio();

    void arm(SleepAlarm current) {
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
          'permission': html.Notification.permission,
          'activeTimers': _timers.length,
          'audioUnlocked': _audioUnlocked,
        },
      );
      // #endregion

      _timers[current.id] = Timer(delay, () {
        _onFire(current, rearm: true, armFn: arm);
      });
    }

    arm(alarm);
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
    audio.onEnded.listen((_) {
      // Keep object URL for looping players; revoke on dismiss.
    });
    return audio;
  }

  void _onFire(
    SleepAlarm current, {
    required bool rearm,
    void Function(SleepAlarm)? armFn,
  }) {
    final visibility = html.document.visibilityState;
    var notifOk = false;
    String? notifError;

    try {
      html.Notification(
        current.label,
        body: 'Time to wake up. (Web reminder — tab must stay open)',
      );
      notifOk = true;
    } catch (e) {
      // Some browsers block Notification construction even after grant.
      notifError = '$e';
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
          'permission': html.Notification.permission,
          'visibility': visibility,
          'soundPlayed': soundPlayed,
          'soundError': soundError,
          'overlayShown': overlayShown,
          'audioUnlocked': _audioUnlocked,
          'hasSoundPath': true,
        },
        runId: 'post-fix',
      );
      // #endregion
      // #region agent log
      agentDebugLog(
        hypothesisId: 'D',
        location: 'alarm_scheduler_web.dart:Timer.fire',
        message: 'web alarm ring attempt',
        data: {
          'alarmId': current.id,
          'soundPlayed': soundPlayed,
          'overlayShown': overlayShown,
          'soundError': soundError,
        },
        runId: 'post-fix',
      );
      // #endregion
    }();

    if (rearm && current.repeatDays.isNotEmpty && current.isEnabled && armFn != null) {
      armFn(current);
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
        runId: 'post-fix',
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
      },
    );
    // #endregion
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
