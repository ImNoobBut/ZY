import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import 'core/config/app_config.dart';
import 'core/models/models.dart';
import 'core/services/admin_service.dart';
import 'core/services/auth_service.dart';
import 'core/services/spotify_service.dart';
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
    required this.sync,
  });

  final AppConfig config;
  final LocalStore store;
  final SpotifyService spotify;
  /// Device tokens / pairing for auth + sync (not Remote Admin UI).
  final AdminService admin;
  final AuthService auth;
  final SyncService sync;

  UserPreferences preferences = UserPreferences();
  SleepRoutine? activeRoutine;
  RoutineState routineState = RoutineState.idle;
  String musicLabel = 'Not configured yet';
  String? errorMessage;
  String? infoMessage;
  bool busy = false;
  bool ready = false;

  Timer? _ticker;
  StreamSubscription<Uri>? _linkSub;

  bool get isLoggedIn => auth.isLoggedIn;

  Future<void> bootstrap() async {
    WidgetsBinding.instance.addObserver(this);
    preferences = await store.loadPreferences();
    activeRoutine = await store.loadActiveRoutine();
    await spotify.restore();
    await admin.restore();
    await auth.restore();

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

    _reconcileRoutine();
    _refreshMusicLabel();
    ready = true;
    notifyListeners();
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

  static String _userFacingError(Object e) {
    final raw = '$e';
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }
    return raw;
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
      errorMessage = _userFacingError(e);
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
      errorMessage = _userFacingError(e);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<String?> requestPasswordReset({required String email}) async {
    busy = true;
    errorMessage = null;
    infoMessage = null;
    notifyListeners();
    try {
      final result = await auth.requestPasswordReset(email: email);
      infoMessage = result.message;
      return result.devResetCode;
    } catch (e) {
      errorMessage = _userFacingError(e);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
  }) async {
    busy = true;
    errorMessage = null;
    infoMessage = null;
    notifyListeners();
    try {
      await auth.resetPassword(email: email, code: code, password: password);
      infoMessage = 'Password updated. You can sign in now.';
    } catch (e) {
      errorMessage = _userFacingError(e);
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
    this.activeRoutine = activeRoutine;
    _reconcileRoutine();
    _refreshMusicLabel();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(sync.syncNow());
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
    _linkSub?.cancel();
    super.dispose();
  }

  Future<void> connectSpotifyDemo() async {
    await spotify.connectDemo();
    infoMessage = 'Spotify demo connected.';
    errorMessage = null;
    _refreshMusicLabel();
    notifyListeners();
  }

  Future<void> completeOnboarding({required int timerMinutes}) async {
    preferences.hasCompletedOnboarding = true;
    preferences.defaultSleepTimerSeconds = timerMinutes * 60;
    preferences.touch();
    await store.savePreferences(preferences);
    unawaited(sync.enqueuePreferences(preferences));
    notifyListeners();
  }

  Future<void> setDefaultTimerMinutes(int minutes) async {
    preferences.defaultSleepTimerSeconds = clampSleepTimerMinutes(minutes) * 60;
    preferences.touch();
    await store.savePreferences(preferences);
    unawaited(sync.enqueuePreferences(preferences));
    notifyListeners();
  }

  Future<void> startRoutine() async {
    if (busy) return;
    busy = true;
    errorMessage = null;
    infoMessage = null;
    notifyListeners();
    try {
      if (!spotify.isAuthenticated) {
        errorMessage = 'Connect Spotify in Settings before starting the timer.';
        routineState = RoutineState.idle;
        return;
      }
      final items = preferences.selectedSpotifyItems;

      routineState = RoutineState.starting;
      try {
        if (items.isNotEmpty) {
          if (preferences.isSpotifyContextSelection) {
            await spotify.play(items.first.uri);
          } else {
            await spotify.playUris(items.map((item) => item.uri).toList());
          }
          musicLabel = preferences.spotifySelectionLabel ?? 'Spotify';
        } else {
          // No in-app selection: attach timer to whatever Spotify is already on.
          final nowPlaying = await spotify.getNowPlaying();
          if (nowPlaying == null) {
            errorMessage =
                'Nothing is playing on Spotify. Start music there, or choose '
                'a track/playlist in the app, then try again.';
            routineState = RoutineState.idle;
            return;
          }
          if (!nowPlaying.isPlaying) {
            await spotify.resume();
          }
          musicLabel = nowPlaying.title;
        }
        routineState = RoutineState.playing;
      } catch (e) {
        errorMessage =
            'Could not start Spotify playback. Open Spotify, play a track once '
            'on an active device, then try again.\n$e';
        routineState = RoutineState.idle;
        return;
      }

      final now = DateTime.now();
      final duration = preferences.defaultSleepTimerSeconds;
      activeRoutine = SleepRoutine(
        id: const Uuid().v4(),
        sleepTimerDurationSeconds: duration,
        musicSource: MusicSource.spotify,
        startedAt: now,
        endsAt: now.add(Duration(seconds: duration)),
      );
      await store.saveActiveRoutine(activeRoutine);
      unawaited(sync.enqueueRoutine(activeRoutine));
      routineState = RoutineState.timerRunning;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> endRoutine({String? notes}) async {
    await spotify.pause();

    activeRoutine = null;
    await store.saveActiveRoutine(null);
    unawaited(sync.enqueueRoutine(null));
    routineState = RoutineState.idle;
    _refreshMusicLabel();
    if (notes != null && notes.isNotEmpty) {
      infoMessage = notes == 'Timer completed'
          ? 'Timer ended — Spotify paused.'
          : notes;
    }
    notifyListeners();
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
    notifyListeners();
  }

  void _reconcileRoutine() {
    final routine = activeRoutine;
    if (routine?.startedAt == null || routine?.endsAt == null) {
      final wasRunning = routineState == RoutineState.timerRunning;
      routineState = RoutineState.idle;
      if (wasRunning) {
        unawaited(_stopPlaybackOnly());
      }
      return;
    }
    if (DateTime.now().isAfter(routine!.endsAt!)) {
      unawaited(endRoutine(notes: 'Timer completed'));
      return;
    }
    routineState = RoutineState.timerRunning;
  }

  Future<void> _stopPlaybackOnly() async {
    await spotify.pause();
    _refreshMusicLabel();
    notifyListeners();
  }

  Duration? remaining() {
    final ends = activeRoutine?.endsAt;
    if (ends == null) return null;
    final left = ends.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  void _refreshMusicLabel() {
    if (!spotify.isAuthenticated) {
      musicLabel = 'Connect Spotify';
      return;
    }
    final label = preferences.spotifySelectionLabel;
    if (label != null) {
      musicLabel = label;
    } else {
      musicLabel = 'Spotify — current playback or pick a track';
    }
  }

  Future<void> _persistSpotifySelection({String? info}) async {
    preferences.syncSpotifyLegacyFields();
    preferences.touch();
    await store.savePreferences(preferences);
    unawaited(sync.enqueuePreferences(preferences));
    _refreshMusicLabel();
    if (info != null) infoMessage = info;
    notifyListeners();
  }

  /// Toggle a track in the queue. Returns true if added, false if removed.
  Future<bool> toggleSpotifyTrack({
    required String uri,
    required String title,
  }) async {
    if (preferences.isSpotifyContextSelection) {
      preferences.selectedSpotifyItems = [];
    }
    final existing = preferences.selectedSpotifyItems.indexWhere(
      (item) => item.uri == uri,
    );
    final added = existing < 0;
    if (added) {
      preferences.selectedSpotifyItems.add(
        SpotifySelectionItem(uri: uri, title: title),
      );
    } else {
      preferences.selectedSpotifyItems.removeAt(existing);
    }
    await _persistSpotifySelection(
      info: added
          ? 'Added "$title" to the timer queue.'
          : 'Removed "$title" from the timer queue.',
    );
    return added;
  }

  Future<void> selectSpotifyContext({
    required String uri,
    required String title,
  }) async {
    preferences.selectedSpotifyItems = [
      SpotifySelectionItem(uri: uri, title: title),
    ];
    await _persistSpotifySelection(
      info: 'Selected "$title" for the timer.',
    );
  }

  Future<void> removeSpotifySelection(String uri) async {
    preferences.selectedSpotifyItems.removeWhere((item) => item.uri == uri);
    await _persistSpotifySelection();
  }

  Future<void> clearSpotifySelection() async {
    preferences.selectedSpotifyItems = [];
    await _persistSpotifySelection();
  }

  Future<void> disconnectSpotify() async {
    await spotify.logout();
    await clearSpotifySelection();
    infoMessage = 'Spotify disconnected.';
    errorMessage = null;
    notifyListeners();
  }

  Future<void> syncNow() => sync.syncNow();

  Future<void> joinSyncAccount(String pairingCode) async {
    await sync.joinWithPairingCode(pairingCode);
    infoMessage = 'Joined sync account. Pairing code for this device: ${admin.pairingCode}.';
    errorMessage = sync.lastError;
    notifyListeners();
  }
}
