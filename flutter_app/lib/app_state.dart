import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'core/config/app_config.dart';
import 'core/models/models.dart';
import 'core/services/admin_service.dart';
import 'core/services/quiet_audio_service.dart';
import 'core/services/spotify_service.dart';
import 'core/storage/local_store.dart';

class AppState extends ChangeNotifier {
  AppState({
    required this.config,
    required this.store,
    required this.spotify,
    required this.admin,
    required this.audio,
  });

  final AppConfig config;
  final LocalStore store;
  final SpotifyService spotify;
  final AdminService admin;
  final QuietAudioService audio;

  UserPreferences preferences = UserPreferences();
  List<SleepAlarm> alarms = [];
  SleepRoutine? activeRoutine;
  RoutineState routineState = RoutineState.idle;
  String musicLabel = 'Not configured yet';
  String? errorMessage;
  String? infoMessage;
  bool busy = false;
  bool ready = false;

  Timer? _ticker;

  Future<void> bootstrap() async {
    preferences = await store.loadPreferences();
    alarms = await store.loadAlarms();
    activeRoutine = await store.loadActiveRoutine();
    await spotify.restore();
    await admin.restore();

    // Finish Spotify OAuth if Spotify redirected back to our web callback URL.
    try {
      final completed = await spotify.tryCompleteFromCurrentUri(Uri.base);
      if (completed) {
        infoMessage = 'Spotify connected.';
      }
    } catch (e) {
      errorMessage = '$e';
    }

    _reconcileRoutine();
    _refreshMusicLabel();
    ready = true;
    notifyListeners();
    if (preferences.remoteMonitoringOptIn) {
      unawaited(checkInIfNeeded());
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    audio.dispose();
    super.dispose();
  }

  Future<void> completeOnboarding({
    required int timerMinutes,
    required bool alarmEnabled,
    required int bedtimeHour,
    required int bedtimeMinute,
    required int wakeHour,
    required int wakeMinute,
  }) async {
    preferences.hasCompletedOnboarding = true;
    preferences.defaultSleepTimerSeconds = timerMinutes * 60;
    preferences.defaultAlarmEnabled = alarmEnabled;
    preferences.preferredBedtimeHour = bedtimeHour;
    preferences.preferredBedtimeMinute = bedtimeMinute;
    preferences.preferredWakeHour = wakeHour;
    preferences.preferredWakeMinute = wakeMinute;
    await store.savePreferences(preferences);
    if (alarmEnabled && alarms.isEmpty) {
      alarms = [
        SleepAlarm(
          id: const Uuid().v4(),
          hour: wakeHour,
          minute: wakeMinute,
        ),
      ];
      await store.saveAlarms(alarms);
    }
    notifyListeners();
  }

  Future<void> setDefaultTimerMinutes(int minutes) async {
    preferences.defaultSleepTimerSeconds = minutes.clamp(1, 180) * 60;
    await store.savePreferences(preferences);
    notifyListeners();
  }

  Future<void> startRoutine() async {
    if (busy) return;
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      routineState = RoutineState.starting;
      final useSpotify = spotify.isAuthenticated && preferences.selectedSpotifyUri != null;
      if (useSpotify) {
        try {
          await spotify.play(preferences.selectedSpotifyUri!);
          musicLabel = preferences.selectedSpotifyTitle ?? 'Spotify';
          routineState = RoutineState.playing;
        } catch (e) {
          routineState = RoutineState.failed;
          errorMessage = e.toString();
          return;
        }
      } else {
        await audio.play();
        musicLabel = 'Quiet night tone';
        routineState = RoutineState.playing;
      }

      final now = DateTime.now();
      final duration = preferences.defaultSleepTimerSeconds;
      final enabledAlarm = _firstEnabledAlarm();
      activeRoutine = SleepRoutine(
        id: const Uuid().v4(),
        sleepTimerDurationSeconds: duration,
        musicSource: useSpotify ? MusicSource.spotify : MusicSource.local,
        startedAt: now,
        endsAt: now.add(Duration(seconds: duration)),
        alarmId: enabledAlarm?.id,
      );
      await store.saveActiveRoutine(activeRoutine);
      routineState = RoutineState.timerRunning;
      if (preferences.remoteMonitoringOptIn) {
        unawaited(checkInIfNeeded());
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> endRoutine() async {
    await audio.stop();
    await spotify.pause();
    activeRoutine = null;
    await store.saveActiveRoutine(null);
    routineState = RoutineState.idle;
    _refreshMusicLabel();
    notifyListeners();
    if (preferences.remoteMonitoringOptIn) {
      unawaited(checkInIfNeeded());
    }
  }

  void _onTick() {
    final routine = activeRoutine;
    if (routine?.endsAt == null) return;
    if (routineState != RoutineState.timerRunning) return;
    if (DateTime.now().isAfter(routine!.endsAt!)) {
      unawaited(endRoutine());
    } else {
      notifyListeners();
    }
  }

  void _reconcileRoutine() {
    final routine = activeRoutine;
    if (routine?.startedAt == null || routine?.endsAt == null) {
      routineState = RoutineState.idle;
      return;
    }
    if (DateTime.now().isAfter(routine!.endsAt!)) {
      unawaited(endRoutine());
      return;
    }
    routineState = RoutineState.timerRunning;
  }

  Duration? remaining() {
    final ends = activeRoutine?.endsAt;
    if (ends == null) return null;
    final left = ends.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  void _refreshMusicLabel() {
    if (preferences.selectedSpotifyTitle != null && spotify.isAuthenticated) {
      musicLabel = preferences.selectedSpotifyTitle!;
    } else if (spotify.isAuthenticated) {
      musicLabel = 'Spotify';
    } else if (audio.isPlaying) {
      musicLabel = 'Quiet night tone';
    } else if (routineState == RoutineState.timerRunning) {
      musicLabel = 'Quiet night';
    } else {
      musicLabel = 'Not configured yet';
    }
  }

  Future<void> saveAlarms(List<SleepAlarm> next) async {
    alarms = next;
    await store.saveAlarms(alarms);
    notifyListeners();
  }

  Future<void> selectSpotify({required String uri, required String title}) async {
    preferences.selectedSpotifyUri = uri;
    preferences.selectedSpotifyTitle = title;
    await store.savePreferences(preferences);
    _refreshMusicLabel();
    infoMessage = 'Selected “$title” for bedtime.';
    notifyListeners();
  }

  Future<void> setRemoteOptIn(bool enabled) async {
    if (!enabled) {
      preferences.remoteMonitoringOptIn = false;
      await store.savePreferences(preferences);
      infoMessage = 'Remote monitoring off.';
      errorMessage = null;
      notifyListeners();
      return;
    }

    // Register first; only persist opt-in after the backend accepts it.
    try {
      if (!admin.isRegistered) {
        await admin.register(displayName: 'Zy Flutter');
      }
      preferences.remoteMonitoringOptIn = true;
      await store.savePreferences(preferences);
      await checkInIfNeeded();
      errorMessage = null;
      infoMessage = 'Remote monitoring on. Share pairing code ${admin.pairingCode}.';
    } catch (e) {
      preferences.remoteMonitoringOptIn = false;
      await store.savePreferences(preferences);
      errorMessage =
          'Could not reach Admin backend at ${config.backendBaseUrl}. '
          'Start it with: python -m uvicorn main:app --host 127.0.0.1 --port 8081\n$e';
      infoMessage = null;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> checkInIfNeeded() async {
    if (!preferences.remoteMonitoringOptIn || !admin.isRegistered) return;
    final enabledAlarm = _firstEnabledAlarm();
    final status = DeviceStatus(
      batteryLevel: kIsWeb ? null : 0.8,
      isCharging: kIsWeb ? null : false,
      routineActive: routineState == RoutineState.timerRunning,
      routineStartedAt: activeRoutine?.startedAt,
      sleepTimerEndsAt: activeRoutine?.endsAt,
      spotifyConnected: spotify.isAuthenticated,
      alarmEnabled: enabledAlarm != null,
      nextAlarm: enabledAlarm == null
          ? null
          : DateTime(
              DateTime.now().year,
              DateTime.now().month,
              DateTime.now().day,
              enabledAlarm.hour,
              enabledAlarm.minute,
            ),
      isPlayingOwnAudio: audio.isPlaying,
      lastCheckIn: DateTime.now(),
    );
    await admin.checkIn(status);
    preferences.lastSuccessfulCheckInIso = status.lastCheckIn.toIso8601String();
    await store.savePreferences(preferences);
    notifyListeners();
  }

  Future<void> disconnectAdmin() async {
    await admin.clear();
    preferences.remoteMonitoringOptIn = false;
    preferences.lastSuccessfulCheckInIso = null;
    await store.savePreferences(preferences);
    notifyListeners();
  }

  Future<void> setAdminPin(String pin) async {
    final normalized = pin.trim();
    if (normalized.length < 4 || normalized.length > 8 || int.tryParse(normalized) == null) {
      throw Exception('Choose a 4–8 digit PIN.');
    }
    final hash = sha256.convert(utf8.encode('zy-salt:$normalized')).toString();
    await store.saveAdminPinHash(hash);
  }

  Future<bool> hasAdminPin() async => (await store.loadAdminPinHash()) != null;

  Future<bool> verifyAdminPin(String pin) async {
    final hash = await store.loadAdminPinHash();
    if (hash == null) return false;
    final attempt = sha256.convert(utf8.encode('zy-salt:${pin.trim()}')).toString();
    return hash == attempt;
  }

  SleepAlarm? _firstEnabledAlarm() {
    for (final alarm in alarms) {
      if (alarm.isEnabled) return alarm;
    }
    return null;
  }
}
