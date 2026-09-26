import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'core/config/app_config.dart';
import 'core/debug/agent_debug_log.dart';
import 'core/models/models.dart';
import 'core/services/admin_service.dart';
import 'core/services/alarm_scheduler.dart';
import 'core/services/auth_service.dart';
import 'core/services/quiet_audio_service.dart';
import 'core/services/spotify_service.dart';
import 'core/services/streak_calculator.dart';
import 'core/services/sync_service.dart';
import 'core/storage/local_store.dart';
import 'core/web/web_oauth.dart';

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState({
    required this.config,
    required this.store,
    required this.spotify,
    required this.admin,
    required this.auth,
    required this.audio,
    required this.alarmScheduler,
    required this.sync,
  });

  final AppConfig config;
  final LocalStore store;
  final SpotifyService spotify;
  final AdminService admin;
  final AuthService auth;
  final QuietAudioService audio;
  final AlarmScheduler alarmScheduler;
  final SyncService sync;

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
  Timer? _adminCommandPollTimer;
  bool _appInForeground = true;
  StreamSubscription<Uri>? _linkSub;

  int get currentStreak => StreakCalculator.currentStreak(
        sessions: sessions,
        bedtimeHour: preferences.preferredBedtimeHour,
        bedtimeMinute: preferences.preferredBedtimeMinute,
      );

  bool get isLoggedIn => auth.isLoggedIn;

  Future<void> bootstrap() async {
    WidgetsBinding.instance.addObserver(this);
    preferences = await store.loadPreferences();
    alarms = await store.loadAlarms();
    sessions = await store.loadSessions();
    activeRoutine = await store.loadActiveRoutine();
    await spotify.restore();
    await admin.restore();
    await auth.restore();
    await alarmScheduler.initialize();
    alarmsPermissionGranted = await alarmScheduler.hasPermission();

    await sync.start(onRemoteApplied: _applyRemoteSync);
    sync.addListener(_onSyncChanged);

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

    try {
      await alarmScheduler.reconcile(alarms);
      await _syncBedtimeReminder();
      alarmsPermissionGranted = await alarmScheduler.hasPermission();
    } catch (e) {
      // Must not block runApp — web/iOS Safari often denies notifications.
      alarmsPermissionGranted = false;
      errorMessage ??= 'Could not schedule alarms: $e';
    }

    // #region agent log
    agentDebugLog(
      hypothesisId: 'E',
      location: 'app_state.dart:bootstrap',
      message: 'bootstrap alarm state',
      data: {
        'granted': alarmsPermissionGranted,
        'bestEffort': alarmScheduler.isBestEffortOnly,
        'needsSettings': alarmScheduler.permissionNeedsSystemSettings,
        'errorSet': errorMessage != null,
        'errorIsNotifHint': errorMessage?.contains('Notifications are blocked') == true,
        'enabledAlarms': alarms.where((a) => a.isEnabled).length,
      },
    );
    // #endregion

    _reconcileRoutine();
    _refreshMusicLabel();
    ready = true;
    notifyListeners();
    if (preferences.remoteMonitoringOptIn) {
      _startAdminCommandPolling();
      unawaited(pollRemoteAdminAndCheckIn());
    }
    if (isLoggedIn) {
      unawaited(sync.syncNow());
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void clearMessages() {
    errorMessage = null;
    infoMessage = null;
    notifyListeners();
  }

  Future<void> registerAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {
    busy = true;
    errorMessage = null;
    infoMessage = null;
    notifyListeners();
    try {
      final profile = await auth.register(
        email: email,
        password: password,
        displayName: displayName,
      );
      preferences.displayName = profile.displayName;
      preferences.touch();
      await store.savePreferences(preferences);
      await sync.seedLocalSnapshot();
      unawaited(sync.syncNow(forcePullAll: true));
      infoMessage = 'Account created.';
    } catch (e) {
      errorMessage = '$e';
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> loginAccount({
    required String email,
    required String password,
  }) async {
    busy = true;
    errorMessage = null;
    infoMessage = null;
    notifyListeners();
    try {
      final profile = await auth.login(email: email, password: password);
      if (profile.displayName.isNotEmpty) {
        preferences.displayName = profile.displayName;
        preferences.touch();
        await store.savePreferences(preferences);
      }
      await store.saveSyncCursor(null);
      unawaited(sync.syncNow(forcePullAll: true));
      infoMessage = 'Signed in.';
    } catch (e) {
      errorMessage = '$e';
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> updateDisplayName(String displayName) async {
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      final profile = await auth.updateDisplayName(displayName);
      preferences.displayName = profile.displayName;
      preferences.touch();
      await store.savePreferences(preferences);
      unawaited(sync.enqueuePreferences(preferences));
      infoMessage = 'Name updated.';
    } catch (e) {
      errorMessage = '$e';
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    busy = true;
    notifyListeners();
    try {
      await auth.signOut();
      infoMessage = 'Signed out.';
      errorMessage = null;
    } catch (e) {
      errorMessage = '$e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _onSyncChanged() => notifyListeners();

  Future<void> _applyRemoteSync({
    required UserPreferences preferences,
    required List<SleepAlarm> alarms,
    required List<SleepSessionRecord> sessions,
    required SleepRoutine? activeRoutine,
  }) async {
    this.preferences = preferences;
    this.alarms = alarms;
    this.sessions = sessions;
    this.activeRoutine = activeRoutine;
    await alarmScheduler.reconcile(alarms);
    await _syncBedtimeReminder();
    _reconcileRoutine();
    _refreshMusicLabel();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appInForeground = true;
      unawaited(sync.syncNow());
      if (preferences.remoteMonitoringOptIn) {
        _startAdminCommandPolling();
        unawaited(pollRemoteAdminAndCheckIn());
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _appInForeground = false;
      _stopAdminCommandPolling();
    }
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
    WidgetsBinding.instance.removeObserver(this);
    sync.removeListener(_onSyncChanged);
    sync.disposeService();
    _ticker?.cancel();
    _stopAdminCommandPolling();
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
    // Always re-arm: web rings in-tab even without notification permission.
    try {
      await alarmScheduler.reconcile(alarms);
      await _syncBedtimeReminder();
    } catch (_) {}
    if (alarmsPermissionGranted == true) {
      infoMessage = 'Alarm permission granted.';
      errorMessage = null;
    } else if (alarmScheduler.isBestEffortOnly) {
      // Phone web (Android Chrome / iOS Safari): notifications are optional.
      // Never put browser-settings copy into errorMessage — Home shows it in red.
      infoMessage = alarmScheduler.permissionNeedsSystemSettings
          ? 'Notifications blocked in the browser. In-tab alarms still work while this tab stays open — see Alarms for how to re-enable.'
          : 'In-tab alarms still work while this tab stays open. Notifications are optional on web.';
      errorMessage = null;
    } else {
      // Native Android / iOS: permission is required for real wake alarms.
      errorMessage = alarmScheduler.permissionNeedsSystemSettings
          ? alarmScheduler.permissionSettingsHint
          : 'Alarm permission is off. Enable it from the Alarms tab to schedule wake alarms.';
      infoMessage = null;
    }
    // #region agent log
    agentDebugLog(
      hypothesisId: 'A',
      location: 'app_state.dart:requestAlarmPermission',
      message: 'permission result wrote messages',
      data: {
        'granted': alarmsPermissionGranted,
        'bestEffort': alarmScheduler.isBestEffortOnly,
        'needsSettings': alarmScheduler.permissionNeedsSystemSettings,
        'errorSet': errorMessage != null,
        'errorPreview': errorMessage == null
            ? null
            : (errorMessage!.length > 80
                ? '${errorMessage!.substring(0, 80)}…'
                : errorMessage),
        'infoPreview': infoMessage == null
            ? null
            : (infoMessage!.length > 80
                ? '${infoMessage!.substring(0, 80)}…'
                : infoMessage),
        'enabledAlarms': alarms.where((a) => a.isEnabled).length,
      },
      runId: 'post-fix',
    );
    // #endregion
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
    preferences.touch();
    await store.savePreferences(preferences);
    unawaited(sync.enqueuePreferences(preferences));
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
      unawaited(sync.enqueueAlarms(alarms));
      await alarmScheduler.reconcile(alarms);
    }
    await _syncBedtimeReminder();
    notifyListeners();
  }

  Future<void> setDefaultTimerMinutes(int minutes) async {
    preferences.defaultSleepTimerSeconds = minutes.clamp(1, 180) * 60;
    preferences.touch();
    await store.savePreferences(preferences);
    unawaited(sync.enqueuePreferences(preferences));
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
    preferences.touch();
    await store.savePreferences(preferences);
    unawaited(sync.enqueuePreferences(preferences));
    await _syncBedtimeReminder();
    notifyListeners();
  }

  Future<void> setQuietSound(QuietSound sound) async {
    preferences.selectedQuietSound = sound;
    preferences.touch();
    await store.savePreferences(preferences);
    unawaited(sync.enqueuePreferences(preferences));
    final localRoutineActive = routineState == RoutineState.timerRunning &&
        activeRoutine?.musicSource == MusicSource.local;
    if (localRoutineActive) {
      final ok = await audio.play(sound);
      if (!ok) {
        errorMessage = audio.lastError ?? 'Could not play quiet sound.';
      } else {
        errorMessage = null;
        musicLabel = sound.displayName;
      }
    } else {
      _refreshMusicLabel();
    }
    notifyListeners();
  }

  Future<void> previewQuietSound(QuietSound sound) async {
    final localRoutineActive = routineState == RoutineState.timerRunning &&
        activeRoutine?.musicSource == MusicSource.local;
    // During a local routine, switch the looping tone instead of a timed preview.
    final ok = localRoutineActive
        ? await audio.play(sound)
        : await audio.preview(sound);
    if (!ok) {
      errorMessage = audio.lastError ?? 'Could not preview quiet sound.';
    } else {
      errorMessage = null;
      if (localRoutineActive) {
        musicLabel = sound.displayName;
      }
    }
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
          final ok = await audio.play(preferences.selectedQuietSound);
          musicLabel =
              '${preferences.selectedQuietSound.displayName} (Spotify device offline)';
          routineState = RoutineState.playing;
          infoMessage =
              'Spotify had no active device, so quiet in-app audio started instead. '
              'Open Spotify, play a track once, then retry for Spotify playback.\n$e';
          if (!ok) {
            errorMessage = audio.lastError ?? 'Could not start quiet sound.';
          }
        }
      } else {
        final ok = await audio.play(preferences.selectedQuietSound);
        musicLabel = preferences.selectedQuietSound.displayName;
        routineState = RoutineState.playing;
        if (!ok) {
          errorMessage = audio.lastError ?? 'Could not start quiet sound.';
        }
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
      unawaited(sync.enqueueRoutine(activeRoutine));
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
    unawaited(sync.enqueueSession(record));

    activeRoutine = null;
    await store.saveActiveRoutine(null);
    unawaited(sync.enqueueRoutine(null));
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
    if (routine.musicSource == MusicSource.local) {
      unawaited(_resumeLocalAudioAfterReconcile(left));
    }
  }

  Future<void> _resumeLocalAudioAfterReconcile(Duration? left) async {
    final ok = await audio.play(preferences.selectedQuietSound);
    if (!ok) {
      errorMessage = audio.lastError ??
          'Quiet sound did not resume after reload. Tap Start again or Preview a tone.';
      notifyListeners();
      return;
    }
    musicLabel = preferences.selectedQuietSound.displayName;
    if (left != null && left.inSeconds <= kFadeOutSeconds && audio.isPlaying) {
      fadeStarted = true;
      unawaited(audio.fadeOut(duration: left));
    }
    notifyListeners();
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
    final previousIds = alarms.map((a) => a.id).toSet();
    final now = DateTime.now().toUtc();
    alarms = next.map((a) {
      a.touch();
      return a;
    }).toList();
    await store.saveAlarms(alarms);
    unawaited(sync.enqueueAlarms(alarms));
    for (final id in previousIds.difference(alarms.map((a) => a.id).toSet())) {
      unawaited(sync.enqueueAlarmDeleted(id, now));
    }
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
        // #region agent log
        agentDebugLog(
          hypothesisId: 'E',
          location: 'app_state.dart:saveAlarms',
          message: 'alarms saved and reconciled',
          data: {
            'enabledCount': enabled.length,
            'permission': alarmsPermissionGranted,
            'bestEffort': alarmScheduler.isBestEffortOnly,
            'nextFire': nextFire.isEmpty ? null : nextFire.first.toIso8601String(),
            'alarms': enabled
                .map((a) => {
                      'id': a.id,
                      'hm': '${a.hour}:${a.minute}',
                      'days': a.repeatDays.toList(),
                      'next': a.nextFireAfter()?.toIso8601String(),
                    })
                .toList(),
          },
        );
        // #endregion
      }
    } catch (e) {
      // #region agent log
      agentDebugLog(
        hypothesisId: 'A',
        location: 'app_state.dart:saveAlarms',
        message: 'reconcile failed',
        data: {'error': '$e'},
      );
      // #endregion
      errorMessage = 'Could not schedule alarms: $e';
      alarmsPermissionGranted = await alarmScheduler.hasPermission();
    }
    notifyListeners();
  }

  Future<void> selectSpotify({required String uri, required String title}) async {
    preferences.selectedSpotifyUri = uri;
    preferences.selectedSpotifyTitle = title;
    preferences.touch();
    await store.savePreferences(preferences);
    unawaited(sync.enqueuePreferences(preferences));
    _refreshMusicLabel();
    infoMessage = 'Selected "$title" for bedtime.';
    notifyListeners();
  }

  Future<void> clearSpotifySelection() async {
    preferences.selectedSpotifyUri = null;
    preferences.selectedSpotifyTitle = null;
    preferences.touch();
    await store.savePreferences(preferences);
    unawaited(sync.enqueuePreferences(preferences));
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
      preferences.touch();
      await store.savePreferences(preferences);
      unawaited(sync.enqueuePreferences(preferences));
      _stopAdminCommandPolling();
      infoMessage = 'Remote monitoring off.';
      errorMessage = null;
      notifyListeners();
      return;
    }

    try {
      if (!admin.isRegistered) {
        throw Exception('Sign in first, then enable remote monitoring.');
      }
      preferences.remoteMonitoringOptIn = true;
      preferences.touch();
      await store.savePreferences(preferences);
      unawaited(sync.enqueuePreferences(preferences));
      _startAdminCommandPolling();
      await pollRemoteAdminAndCheckIn();
      errorMessage = null;
      infoMessage = 'Remote monitoring on. Share pairing code ${admin.pairingCode}.';
    } catch (e) {
      preferences.remoteMonitoringOptIn = false;
      preferences.touch();
      await store.savePreferences(preferences);
      _stopAdminCommandPolling();
      errorMessage =
          'Could not reach the server at ${config.backendBaseUrl}. Check your connection and try again.\n$e';
      infoMessage = null;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  void _startAdminCommandPolling() {
    _stopAdminCommandPolling();
    if (!preferences.remoteMonitoringOptIn || !admin.isRegistered) return;
    _adminCommandPollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_appInForeground) return;
      unawaited(pollRemoteAdminAndCheckIn());
    });
  }

  void _stopAdminCommandPolling() {
    _adminCommandPollTimer?.cancel();
    _adminCommandPollTimer = null;
  }

  /// Pull pending guardian commands, apply them, ack, then check in status.
  Future<void> pollRemoteAdminAndCheckIn() async {
    if (!preferences.remoteMonitoringOptIn || !admin.isRegistered) return;
    try {
      final commands = await admin.fetchPendingCommands();
      final acked = <String>[];
      for (final cmd in commands) {
        final id = cmd['id'] as String?;
        if (id == null) continue;
        try {
          await _applyAdminCommand(cmd);
          acked.add(id);
        } catch (_) {
          // Leave unacked so a later poll can retry.
        }
      }
      if (acked.isNotEmpty) {
        await admin.ackCommands(acked);
      }
    } catch (_) {
      // Best-effort; check-in still runs below.
    }
    try {
      await checkInIfNeeded();
    } catch (_) {}
  }

  Future<void> _applyAdminCommand(Map<String, dynamic> cmd) async {
    final type = cmd['type'] as String? ?? '';
    final payload = Map<String, dynamic>.from(
      (cmd['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
    switch (type) {
      case 'setAlarmEnabled':
        final enabled = payload['enabled'] as bool? ?? false;
        await _setAlarmEnabledFromRemote(enabled);
      case 'setBedtime':
        final hour = (payload['hour'] as num?)?.toInt();
        final minute = (payload['minute'] as num?)?.toInt();
        if (hour == null || minute == null) {
          throw Exception('Invalid bedtime payload');
        }
        await updateBedtimePrefs(bedtimeHour: hour, bedtimeMinute: minute);
      case 'startRoutine':
        if (routineState == RoutineState.idle) {
          await startRoutine();
        }
      case 'endRoutine':
        if (routineState != RoutineState.idle) {
          await endRoutine();
        }
      case 'stopAudio':
        await audio.cancelFade();
        fadeStarted = false;
        await audio.stop();
        _refreshMusicLabel();
        notifyListeners();
      default:
        throw Exception('Unknown admin command: $type');
    }
  }

  Future<void> _setAlarmEnabledFromRemote(bool enabled) async {
    preferences.defaultAlarmEnabled = enabled;
    preferences.touch();
    await store.savePreferences(preferences);
    unawaited(sync.enqueuePreferences(preferences));

    if (enabled) {
      if (alarms.isEmpty) {
        await saveAlarms([
          SleepAlarm(
            id: const Uuid().v4(),
            hour: preferences.preferredWakeHour,
            minute: preferences.preferredWakeMinute,
            repeatDays: {1, 2, 3, 4, 5},
            isEnabled: true,
          ),
        ]);
      } else {
        await saveAlarms(
          alarms.map((a) => a.copyWith(isEnabled: true)).toList(),
        );
      }
    } else {
      if (alarms.isNotEmpty) {
        await saveAlarms(
          alarms.map((a) => a.copyWith(isEnabled: false)).toList(),
        );
      } else {
        notifyListeners();
      }
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
    preferences.touch();
    await store.savePreferences(preferences);
    unawaited(sync.enqueuePreferences(preferences));
    notifyListeners();
  }

  Future<void> disconnectAdmin() async {
    await admin.revokeAdminTokens();
    _stopAdminCommandPolling();
    await admin.clear();
    preferences.remoteMonitoringOptIn = false;
    preferences.lastSuccessfulCheckInIso = null;
    preferences.touch();
    await store.savePreferences(preferences);
    unawaited(sync.enqueuePreferences(preferences));
    notifyListeners();
  }

  Future<void> syncNow() => sync.syncNow();

  Future<void> joinSyncAccount(String pairingCode) async {
    await sync.joinWithPairingCode(pairingCode);
    infoMessage = 'Joined sync account. Pairing code for this device: ${admin.pairingCode}.';
    errorMessage = sync.lastError;
    notifyListeners();
  }

  Future<void> setAdminPin(String pin) async {
    final normalized = pin.trim();
    if (normalized.length < 4 || normalized.length > 8 || int.tryParse(normalized) == null) {
      throw Exception('Choose a 4–8 digit PIN.');
    }
    final saltBytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final salt = base64UrlEncode(saltBytes);
    final hash = sha256.convert(utf8.encode('$salt:$normalized')).toString();
    await store.saveAdminPinHash('$salt:$hash');
  }

  Future<bool> hasAdminPin() async => (await store.loadAdminPinHash()) != null;

  Future<bool> verifyAdminPin(String pin) async {
    final stored = await store.loadAdminPinHash();
    if (stored == null) return false;
    final normalized = pin.trim();
    // Phase 8+: "salt:hash". Legacy static salt kept for one upgrade cycle.
    if (stored.contains(':') && !stored.startsWith('zy-salt:')) {
      final sep = stored.indexOf(':');
      final salt = stored.substring(0, sep);
      final expected = stored.substring(sep + 1);
      final attempt = sha256.convert(utf8.encode('$salt:$normalized')).toString();
      return attempt == expected;
    }
    final legacy = sha256.convert(utf8.encode('zy-salt:$normalized')).toString();
    if (stored == legacy || stored == 'zy-salt:$legacy') {
      // Re-hash with a random salt on successful unlock.
      await setAdminPin(normalized);
      return true;
    }
    return false;
  }

  SleepAlarm? _firstEnabledAlarm() {
    for (final alarm in alarms) {
      if (alarm.isEnabled) return alarm;
    }
    return null;
  }
}
