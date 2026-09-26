import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

class LocalStore {
  static const _prefsKey = 'user_preferences_v1';
  static const _routineKey = 'active_routine_v1';
  static const _alarmsKey = 'alarms_v1';
  static const _sessionsKey = 'sleep_sessions_v1';
  static const _spotifyTokensKey = 'spotify_tokens_v1';
  static const _adminCredsKey = 'admin_creds_v1';
  static const _adminPinKey = 'admin_pin_hash_v1';
  static const _outboxKey = 'sync_outbox_v1';
  static const _syncCursorKey = 'sync_cursor_v1';
  static const _lastSyncKey = 'sync_last_success_v1';
  static const _maxSessions = 60;

  Future<UserPreferences> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return UserPreferences();
    return UserPreferences.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> savePreferences(UserPreferences preferences) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(preferences.toJson()));
  }

  Future<SleepRoutine?> loadActiveRoutine() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_routineKey);
    if (raw == null) return null;
    return SleepRoutine.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveActiveRoutine(SleepRoutine? routine) async {
    final prefs = await SharedPreferences.getInstance();
    if (routine == null) {
      await prefs.remove(_routineKey);
    } else {
      await prefs.setString(_routineKey, jsonEncode(routine.toJson()));
    }
  }

  Future<List<SleepAlarm>> loadAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_alarmsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => SleepAlarm.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveAlarms(List<SleepAlarm> alarms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _alarmsKey,
      jsonEncode(alarms.map((e) => e.toJson()).toList()),
    );
  }

  Future<List<SleepSessionRecord>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => SleepSessionRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> appendSession(SleepSessionRecord record) async {
    final sessions = await loadSessions();
    sessions.insert(0, record);
    while (sessions.length > _maxSessions) {
      sessions.removeLast();
    }
    await saveSessions(sessions);
  }

  Future<void> saveSessions(List<SleepSessionRecord> sessions) async {
    final trimmed = sessions.length > _maxSessions
        ? sessions.sublist(0, _maxSessions)
        : sessions;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sessionsKey,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }

  Future<List<SyncMutation>> loadOutbox() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_outboxKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => SyncMutation.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveOutbox(List<SyncMutation> mutations) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _outboxKey,
      jsonEncode(mutations.map((e) => e.toJson()).toList()),
    );
  }

  /// Upsert a mutation into the outbox (same entity replaces older pending).
  Future<void> enqueueMutation(SyncMutation mutation) async {
    final box = await loadOutbox();
    box.removeWhere(
      (m) => m.entityType == mutation.entityType && m.entityId == mutation.entityId,
    );
    box.add(mutation);
    await saveOutbox(box);
  }

  Future<String?> loadSyncCursor() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_syncCursorKey);
  }

  Future<void> saveSyncCursor(String? cursor) async {
    final prefs = await SharedPreferences.getInstance();
    if (cursor == null) {
      await prefs.remove(_syncCursorKey);
    } else {
      await prefs.setString(_syncCursorKey, cursor);
    }
  }

  Future<String?> loadLastSyncIso() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastSyncKey);
  }

  Future<void> saveLastSyncIso(String? iso) async {
    final prefs = await SharedPreferences.getInstance();
    if (iso == null) {
      await prefs.remove(_lastSyncKey);
    } else {
      await prefs.setString(_lastSyncKey, iso);
    }
  }

  Future<Map<String, dynamic>?> loadSpotifyTokens() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_spotifyTokensKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> saveSpotifyTokens(Map<String, dynamic>? tokens) async {
    final prefs = await SharedPreferences.getInstance();
    if (tokens == null) {
      await prefs.remove(_spotifyTokensKey);
    } else {
      await prefs.setString(_spotifyTokensKey, jsonEncode(tokens));
    }
  }

  Future<Map<String, dynamic>?> loadAdminCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_adminCredsKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> saveAdminCredentials(Map<String, dynamic>? creds) async {
    final prefs = await SharedPreferences.getInstance();
    if (creds == null) {
      await prefs.remove(_adminCredsKey);
    } else {
      await prefs.setString(_adminCredsKey, jsonEncode(creds));
    }
  }

  Future<String?> loadAdminPinHash() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_adminPinKey);
  }

  Future<void> saveAdminPinHash(String? hash) async {
    final prefs = await SharedPreferences.getInstance();
    if (hash == null) {
      await prefs.remove(_adminPinKey);
    } else {
      await prefs.setString(_adminPinKey, hash);
    }
  }

  static const _pkceKey = 'spotify_pkce_v1';

  Future<void> saveSpotifyPkce({required String verifier, required String state}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pkceKey,
      jsonEncode({'verifier': verifier, 'state': state}),
    );
  }

  Future<Map<String, String>?> loadSpotifyPkce() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pkceKey);
    if (raw == null) return null;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return {
      'verifier': map['verifier'] as String,
      'state': map['state'] as String,
    };
  }

  Future<void> clearSpotifyPkce() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pkceKey);
  }
}
