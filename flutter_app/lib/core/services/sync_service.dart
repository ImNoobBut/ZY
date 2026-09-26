import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/models.dart';
import '../storage/local_store.dart';
import 'admin_service.dart';

typedef SyncApplyCallback = Future<void> Function({
  required UserPreferences preferences,
  required List<SleepAlarm> alarms,
  required List<SleepSessionRecord> sessions,
  required SleepRoutine? activeRoutine,
});

/// Offline-first sync: local outbox → push → pull → LWW merge.
class SyncService extends ChangeNotifier {
  SyncService({
    required this.config,
    required this.store,
    required this.admin,
  });

  final AppConfig config;
  final LocalStore store;
  final AdminService admin;

  bool online = true;
  bool syncing = false;
  String? lastSyncIso;
  String? lastError;
  int pendingCount = 0;

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _debounce;
  SyncApplyCallback? _onRemoteApplied;

  Future<void> start({required SyncApplyCallback onRemoteApplied}) async {
    _onRemoteApplied = onRemoteApplied;
    lastSyncIso = await store.loadLastSyncIso();
    pendingCount = (await store.loadOutbox()).length;
    final results = await Connectivity().checkConnectivity();
    online = _isOnline(results);
    _connSub?.cancel();
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final wasOnline = online;
      online = _isOnline(results);
      notifyListeners();
      if (!wasOnline && online) {
        unawaited(syncNow());
      }
    });
    notifyListeners();
  }

  void disposeService() {
    _connSub?.cancel();
    _debounce?.cancel();
  }

  static bool _isOnline(List<ConnectivityResult> results) {
    if (results.isEmpty) return true;
    return results.any((r) => r != ConnectivityResult.none);
  }

  Future<void> enqueuePreferences(UserPreferences prefs) async {
    await store.enqueueMutation(
      SyncMutation(
        entityType: 'preferences',
        entityId: 'default',
        payload: prefs.toJson(),
        updatedAt: prefs.updatedAt,
      ),
    );
    await _markPendingAndSchedule();
  }

  Future<void> enqueueAlarms(List<SleepAlarm> alarms) async {
    for (final alarm in alarms) {
      await store.enqueueMutation(
        SyncMutation(
          entityType: 'alarm',
          entityId: alarm.id,
          payload: alarm.toJson(),
          updatedAt: alarm.updatedAt,
        ),
      );
    }
    await _markPendingAndSchedule();
  }

  Future<void> enqueueAlarmDeleted(String alarmId, DateTime updatedAt) async {
    await store.enqueueMutation(
      SyncMutation(
        entityType: 'alarm',
        entityId: alarmId,
        payload: const {},
        updatedAt: updatedAt,
        deleted: true,
      ),
    );
    await _markPendingAndSchedule();
  }

  Future<void> enqueueSession(SleepSessionRecord session) async {
    await store.enqueueMutation(
      SyncMutation(
        entityType: 'session',
        entityId: session.id,
        payload: session.toJson(),
        updatedAt: session.updatedAt,
      ),
    );
    await _markPendingAndSchedule();
  }

  Future<void> enqueueRoutine(SleepRoutine? routine) async {
    if (routine == null) {
      await store.enqueueMutation(
        SyncMutation(
          entityType: 'routine',
          entityId: 'active',
          payload: const {},
          updatedAt: DateTime.now().toUtc(),
          deleted: true,
        ),
      );
    } else {
      await store.enqueueMutation(
        SyncMutation(
          entityType: 'routine',
          entityId: 'active',
          payload: routine.toJson(),
          updatedAt: routine.updatedAt,
        ),
      );
    }
    await _markPendingAndSchedule();
  }

  Future<void> _markPendingAndSchedule() async {
    pendingCount = (await store.loadOutbox()).length;
    notifyListeners();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      unawaited(syncNow());
    });
  }

  Future<void> joinWithPairingCode(String code) async {
    await admin.joinAccount(
      pairingCode: code,
      displayName: kIsWeb ? 'Zy Web linked' : 'Zy Flutter linked',
    );
    await store.saveSyncCursor(null);
    await seedLocalSnapshot();
    await syncNow(forcePullAll: true);
  }

  /// Queue current local documents so a new/joined device contributes its state.
  Future<void> seedLocalSnapshot() async {
    final preferences = await store.loadPreferences();
    if (preferences.updatedAt.millisecondsSinceEpoch == 0) {
      preferences.touch();
      await store.savePreferences(preferences);
    }
    await enqueuePreferences(preferences);
    final alarms = await store.loadAlarms();
    if (alarms.isNotEmpty) await enqueueAlarms(alarms);
    final sessions = await store.loadSessions();
    for (final s in sessions) {
      await enqueueSession(s);
    }
    final routine = await store.loadActiveRoutine();
    await enqueueRoutine(routine);
  }

  Future<void> ensureRegistered() async {
    // Email/password auth creates the device; do not auto-register anonymously.
    if (!admin.isRegistered) {
      throw Exception('Sign in required before sync');
    }
  }

  Future<void> syncNow({bool forcePullAll = false}) async {
    if (syncing) return;
    if (!admin.isRegistered) {
      lastError = null;
      notifyListeners();
      return;
    }
    if (!online) {
      lastError = 'Offline — changes stay on this device until you reconnect.';
      notifyListeners();
      return;
    }
    syncing = true;
    lastError = null;
    notifyListeners();
    try {
      await ensureRegistered();
      await _pushOutbox();
      await _pullAndMerge(forcePullAll: forcePullAll);
      lastSyncIso = DateTime.now().toUtc().toIso8601String();
      await store.saveLastSyncIso(lastSyncIso);
      pendingCount = (await store.loadOutbox()).length;
    } catch (e) {
      lastError = '$e';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> _pushOutbox() async {
    final box = await store.loadOutbox();
    if (box.isEmpty) return;
    final res = await _authorizedPost(
      '/v1/sync',
      body: {
        'mutations': box.map((m) => m.toJson()).toList(),
      },
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Sync push failed (${res.statusCode})');
    }
    await store.saveOutbox([]);
  }

  Future<void> _pullAndMerge({bool forcePullAll = false}) async {
    final since = forcePullAll ? null : await store.loadSyncCursor();
    final uri = Uri.parse('${config.backendBaseUrl}/v1/sync').replace(
      queryParameters: since == null || since.isEmpty ? null : {'since': since},
    );
    final res = await _authorizedGet(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Sync pull failed (${res.statusCode})');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final serverTime = json['serverTime'] as String?;
    final changes = (json['changes'] as List?) ?? const [];

    var preferences = await store.loadPreferences();
    var alarms = await store.loadAlarms();
    var sessions = await store.loadSessions();
    var routine = await store.loadActiveRoutine();
    var changed = false;

    for (final raw in changes) {
      final change = raw as Map<String, dynamic>;
      final type = change['entityType'] as String;
      final id = change['entityId'] as String;
      final deleted = change['deleted'] as bool? ?? false;
      final remoteAt = DateTime.tryParse(change['updatedAt'] as String? ?? '')?.toUtc();
      if (remoteAt == null) continue;
      final payload = Map<String, dynamic>.from(change['payload'] as Map? ?? const {});

      switch (type) {
        case 'preferences':
          if (!deleted && remoteAt.isAfter(preferences.updatedAt)) {
            preferences = UserPreferences.fromJson(payload);
            changed = true;
          }
        case 'alarm':
          if (deleted) {
            final before = alarms.length;
            alarms = alarms.where((a) => a.id != id).toList();
            if (alarms.length != before) changed = true;
          } else {
            final remote = SleepAlarm.fromJson(payload);
            final idx = alarms.indexWhere((a) => a.id == id);
            if (idx < 0) {
              alarms = [...alarms, remote];
              changed = true;
            } else if (remoteAt.isAfter(alarms[idx].updatedAt)) {
              alarms = [...alarms]..[idx] = remote;
              changed = true;
            }
          }
        case 'session':
          if (!deleted) {
            final remote = SleepSessionRecord.fromJson(payload);
            final idx = sessions.indexWhere((s) => s.id == id);
            if (idx < 0) {
              sessions = [remote, ...sessions];
              changed = true;
            } else if (remoteAt.isAfter(sessions[idx].updatedAt)) {
              sessions = [...sessions]..[idx] = remote;
              changed = true;
            }
          }
        case 'routine':
          if (deleted) {
            if (routine != null) {
              routine = null;
              changed = true;
            }
          } else {
            final remote = SleepRoutine.fromJson(payload);
            if (routine == null || remoteAt.isAfter(routine.updatedAt)) {
              routine = remote;
              changed = true;
            }
          }
      }
    }

    if (changed) {
      await store.savePreferences(preferences);
      await store.saveAlarms(alarms);
      await store.saveSessions(sessions);
      await store.saveActiveRoutine(routine);
      final apply = _onRemoteApplied;
      if (apply != null) {
        await apply(
          preferences: preferences,
          alarms: alarms,
          sessions: sessions,
          activeRoutine: routine,
        );
      }
    }

    if (serverTime != null) {
      await store.saveSyncCursor(serverTime);
    }
  }

  Future<http.Response> _authorizedGet(Uri uri) async {
    var res = await http.get(
      uri,
      headers: {'Authorization': 'Bearer ${admin.accessToken}'},
    );
    if (res.statusCode == 401 && admin.refreshToken != null) {
      await admin.refreshTokens();
      res = await http.get(
        uri,
        headers: {'Authorization': 'Bearer ${admin.accessToken}'},
      );
    }
    return res;
  }

  Future<http.Response> _authorizedPost(String path, {required Map<String, dynamic> body}) async {
    var res = await http.post(
      Uri.parse('${config.backendBaseUrl}$path'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${admin.accessToken}',
      },
      body: jsonEncode(body),
    );
    if (res.statusCode == 401 && admin.refreshToken != null) {
      await admin.refreshTokens();
      res = await http.post(
        Uri.parse('${config.backendBaseUrl}$path'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${admin.accessToken}',
        },
        body: jsonEncode(body),
      );
    }
    return res;
  }
}
