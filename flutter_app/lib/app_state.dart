import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'core/config/app_config.dart';
import 'core/models/models.dart';
import 'core/services/admin_service.dart';
import 'core/services/alarm_scheduler.dart';
import 'core/services/quiet_audio_service.dart';
import 'core/services/spotify_service.dart';
import 'core/services/streak_calculator.dart';
import 'core/storage/local_store.dart';
import 'core/web/web_oauth.dart';

class AppState extends ChangeNotifier {
  AppState({
    required this.config,
    required this.store,
    required this.spotify,
    required this.admin,
    required this.audio,
    required this.alarmScheduler,
  });

  final AppConfig config;
  final LocalStore store;
  final SpotifyService spotify;
  final AdminService admin;
  final QuietAudioService audio;
  final AlarmScheduler alarmScheduler;

  UserPreferences preferences = UserPreferences();
  List<SleepAlarm> alarms = [];
  List<SleepSessionRecord> sessions = [];
  SleepRoutine? activeRoutine;
  RoutineState routineState = RoutineState.idle;
  String musicLabel = 'Not configured yet';
  String? errorMessage;
  String? infoMessage;
  bool busy = false;
  bool ready = false;
  bool? alarmsPermissionGranted;
  bool fadeStarted = false;

  Timer? _ticker;
  StreamSubscription<Uri>? _linkSub;

  int get currentStreak => StreakCalculator.currentStreak(
        sessions: sessions,
        bedtimeHour: preferences.preferredBedtimeHour,
        bedtimeMinute: preferences.preferredBedtimeMinute,
      );

  Future<void> bootstrap() async {
    preferences = await store.loadPreferences();
    alarms = await store.loadAlarms();
    sessions = await store.loadSessions();
    activeRoutine = await store.loadActiveRoutine();
    await spotify.restore();
    await admin.restore();
    await alarmScheduler.initialize();
    alarmsPermissionGranted = await alarmScheduler.hasPermission();

    try {
      final completed = await spotify.tryCompleteFromCurrentUri(Uri.base);
      if (completed) {
        infoMessage = 'Spotify connected.';
        _refreshMusicLabel();
      }
    } catch (e) {
      errorMessage = '$e';
    } finally {
      if (kIsWeb) clearOAuthCallbackFromBrowserUrl();
    }

    if (!kIsWeb) {
      await _listenForSpotifyDeepLinks();
    }

    await alarmScheduler.reconcile(alarms);
    await _syncBedtimeReminder();

    _reconcileRoutine();
    _refreshMusicLabel();
    ready = true;
    notifyListeners();
    if (preferences.remoteMonitoringOptIn) {
      unawaited(checkInIfNeeded());
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  Future<void> _listenForSpotifyDeepLinks() async {
    final appLinks = AppLinks();
    try {
      final initial = await appLinks.getInitialLink();
      if (initial != null) {
        await _handleIncomingUri(initial);
      }
    } catch (_) {}
    _linkSub = appLinks.uriLinkStream.listen((uri) {
      unawaited(_handleIncomingUri(uri));
    });
  }

  Future<void> _handleIncomingUri(Uri uri) async {
    try {
      final completed = await spotify.tryCompleteFromCurrentUri(uri);
      if (completed) {
        infoMessage = 'Spotify connected.';
        errorMessage = null;
        _refreshMusicLabel();
        notifyListeners();
      }
    } catch (e) {
      errorMessage = '$e';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _linkSub?.cancel();
    audio.dispose();
    super.dispose();
  }

  Future<void> connectSpotifyDemo() async {
    await spotify.connectDemo();
    infoMessage = 'Spotify demo connected.';
    errorMessage = null;
    _refreshMusicLabel();
    notifyListeners();
  }

  Future<void> requestAlarmPermission() async {
    alarmsPermissionGranted = await alarmScheduler.requestPermission();
    if (alarmsPermissionGranted == true) {
      await alarmScheduler.reconcile(alarms);
      await _syncBedtimeReminder();
      infoMessage = 'Alarm permission granted.';
      errorMessage = null;
    } else {
      errorMessage =
          'Alarm permission is off. Enable it from the Alarms tab to schedule wake alarms.';
    }
    notifyListeners();
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
    preferences.bedtimeReminderEnabled = true;
    await store.savePreferences(preferences);
    if (alarmEnabled && alarms.isEmpty) {
      alarms = [
        SleepAlarm(
          id: const Uuid().v4(),
          hour: wakeHour,
          minute: wakeMinute,
          repeatDays: {1, 2, 3, 4, 5},
        ),
      ];
      await store.saveAlarms(alarms);
      await alarmScheduler.reconcile(alarms);
    }
    await _syncBedtimeReminder();
    notifyListeners();
  }

  Future<void> setDefaultTimerMinutes(int minutes) async {
    preferences.defaultSleepTimerSeconds = minutes.clamp(1, 180) * 60;
    await store.savePreferences(preferences);
    notifyListeners();
  }

  Future<void> updateBedtimePrefs({
    int? bedtimeHour,
    int? bedtimeMinute,
    int? wakeHour,
    int? wakeMinute,
    bool? bedtimeReminderEnabled,
  }) async {
    if (bedtimeHour != null) preferences.preferredBedtimeHour = bedtimeHour;
    if (bedtimeMinute != null) preferences.preferredBedtimeMinute = bedtimeMinute;
    if (wakeHour != null) preferences.preferredWakeHour = wakeHour;
    if (wakeMinute != null) preferences.preferredWakeMinute = wakeMinute;
    if (bedtimeReminderEnabled != null) {
      preferences.bedtimeReminderEnabled = bedtimeReminderEnabled;
    }
    await store.savePreferences(preferences);
    await _syncBedtimeReminder();
    notifyListeners();
  }

  Future<void> setQuietSound(QuietSound sound) async {
    preferences.selectedQuietSound = sound;
    await store.savePreferences(preferences);
    _refreshMusicLabel();
    notifyListeners();
  }

  Future<void> previewQuietSound(QuietSound sound) async {
    await audio.preview(sound);
    notifyListeners();
  }

  Future<void> _syncBedtimeReminder() async {
    await alarmScheduler.scheduleBedtimeReminder(
      hour: preferences.preferredBedtimeHour,
      minute: preferences.preferredBedtimeMinute,
      enabled: preferences.bedtimeReminderEnabled,
    );
  }

  Future<void> startRoutine() async {
    if (busy) return;
    busy = true;
    errorMessage = null;
    infoMessage = null;
    fadeStarted = false;
    notifyListeners();
    try {
      routineState = RoutineState.starting;
      final useSpotify = spotify.isAuthenticated && preferences.selectedSpotifyUri != null;
      var playingSpotify = false;
      if (useSpotify) {
        try {
          await spotify.play(preferences.selectedSpotifyUri!);
          musicLabel = preferences.selectedSpotifyTitle ?? 'Spotify';
          routineState = RoutineState.playing;
          playingSpotify = true;
        } catch (e) {
          await audio.play(preferences.selectedQuietSound);
          musicLabel =
              '${preferences.selectedQuietSound.displayName} (Spotify device offline)';
          routineState = RoutineState.playing;
          infoMessage =
              'Spotify had no active device, so quiet in-app audio started instead. '
              'Open Spotify, play a track once, then retry for Spotify playback.\n$e';
        }
      } else {
        await audio.play(preferences.selectedQuietSound);
        musicLabel = preferences.selectedQuietSound.displayName;
        routineState = RoutineState.playing;
      }

      final now = DateTime.now();
      final duration = preferences.defaultSleepTimerSeconds;
      final enabledAlarm = _firstEnabledAlarm();
      activeRoutine = SleepRoutine(
        id: const Uuid().v4(),
        sleepTimerDurationSeconds: duration,
        musicSource: playingSpotify ? MusicSource.spotify : MusicSource.local,
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

  Future<void> endRoutine({String? notes}) async {
    await audio.cancelFade();
    fadeStarted = false;
    final started = activeRoutine?.startedAt ?? DateTime.now();
    final now = DateTime.now();
    await audio.stop();
    await spotify.pause();

    final record = SleepSessionRecord(
      id: const Uuid().v4(),
      startedAt: started,
      musicStoppedAt: now,
      alarmTime: _firstEnabledAlarm()?.nextFireAfter(now),
      completedAt: now,
      notes: notes,
    );
    await store.appendSession(record);
    sessions = await store.loadSessions();

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
    final left = remaining();
    if (left == null) return;

    if (left == Duration.zero || DateTime.now().isAfter(routine!.endsAt!)) {
      unawaited(endRoutine(notes: 'Timer completed'));
      return;
    }

    final usingLocal = routine.musicSource == MusicSource.local;
    if (usingLocal &&
        !fadeStarted &&
        left.inSeconds <= kFadeOutSeconds &&
        audio.isPlaying) {
      fadeStarted = true;
      unawaited(audio.fadeOut(duration: left));
    }
    notifyListeners();
  }

  void _reconcileRoutine() {
    final routine = activeRoutine;
    if (routine?.startedAt == null || routine?.endsAt == null) {
      routineState = RoutineState.idle;
      return;
    }
    if (DateTime.now().isAfter(routine!.endsAt!)) {
      unawaited(endRoutine(notes: 'Timer completed'));
      return;
    }
    routineState = RoutineState.timerRunning;
    final left = remaining();
    if (routine.musicSource == MusicSource.local &&
        left != null &&
        left.inSeconds <= kFadeOutSeconds) {
      fadeStarted = true;
    }
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
    } else if (spotify.isAuthenticated && preferences.selectedSpotifyUri != null) {
      musicLabel = 'Spotify';
    } else if (audio.isPlaying || routineState == RoutineState.timerRunning) {
      musicLabel = preferences.selectedQuietSound.displayName;
    } else {
      musicLabel = preferences.selectedQuietSound.displayName;
    }
  }

  Future<void> saveAlarms(List<SleepAlarm> next) async {
    alarms = next;
    await store.saveAlarms(alarms);
    try {
      await alarmScheduler.reconcile(alarms);
      alarmsPermissionGranted = await alarmScheduler.hasPermission();
      errorMessage = null;
      final enabled = alarms.where((a) => a.isEnabled).toList();
      if (enabled.isNotEmpty) {
        final nextFire = enabled.map((a) => a.nextFireAfter()).whereType<DateTime>().toList()
          ..sort();
        if (nextFire.isNotEmpty) {
          infoMessage =
              'Alarms updated. Next: ${DateFormat('EEE HH:mm').format(nextFire.first)}'
              '${alarmScheduler.isBestEffortOnly ? ' (keep this tab open on web)' : ''}';
        }
      }
    } catch (e) {
      errorMessage = 'Could not schedule alarms: $e';
      alarmsPermissionGranted = await alarmScheduler.hasPermission();
    }
    notifyListeners();
  }

  Future<void> selectSpotify({required String uri, required String title}) async {
    preferences.selectedSpotifyUri = uri;
    preferences.selectedSpotifyTitle = title;
    await store.savePreferences(preferences);
    _refreshMusicLabel();
    infoMessage = 'Selected "$title" for bedtime.';
    notifyListeners();
  }

  Future<void> clearSpotifySelection() async {
    preferences.selectedSpotifyUri = null;
    preferences.selectedSpotifyTitle = null;
    await store.savePreferences(preferences);
    _refreshMusicLabel();
    notifyListeners();
  }

  Future<void> disconnectSpotify() async {
    await spotify.logout();
    await clearSpotifySelection();
    infoMessage = 'Spotify disconnected.';
    errorMessage = null;
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
    final next = enabledAlarm?.nextFireAfter();
    final status = DeviceStatus(
      batteryLevel: kIsWeb ? null : 0.8,
      isCharging: kIsWeb ? null : false,
      routineActive: routineState == RoutineState.timerRunning,
      routineStartedAt: activeRoutine?.startedAt,
      sleepTimerEndsAt: activeRoutine?.endsAt,
      spotifyConnected: spotify.isAuthenticated,
      alarmEnabled: enabledAlarm != null,
      nextAlarm: next,
      isPlayingOwnAudio: audio.isPlaying,
      lastCheckIn: DateTime.now(),
      preferredBedtime: preferences.preferredBedtimeLabel,
      currentStreak: currentStreak,
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
