import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'secure_store.dart';
import 'secure_store_factory.dart';

class LocalStore {
  LocalStore({SecureStore? secureStore})
      : _secure = secureStore ?? createSecureStore();

  final SecureStore _secure;

  static const _prefsKey = 'user_preferences_v1';
  static const _routineKey = 'active_routine_v1';
  static const _alarmsKey = 'alarms_v1';
  static const _sessionsKey = 'sleep_sessions_v1';
  static const _spotifyTokensKey = 'spotify_tokens_v1';
  static const _adminCredsKey = 'admin_creds_v1';
  static const _adminPinKey = 'admin_pin_hash_v1';
  static const _userProfileKey = 'user_profile_v1';
  static const _outboxKey = 'sync_outbox_v1';
  static const _syncCursorKey = 'sync_cursor_v1';
  static const _lastSyncKey = 'sync_last_success_v1';
  static const _pkceKey = 'spotify_pkce_v1';
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
    return _loadSecureJson(_spotifyTokensKey);
  }

  Future<void> saveSpotifyTokens(Map<String, dynamic>? tokens) async {
    await _saveSecureJson(_spotifyTokensKey, tokens);
  }

  Future<Map<String, dynamic>?> loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userProfileKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> saveUserProfile(Map<String, dynamic>? profile) async {
    final prefs = await SharedPreferences.getInstance();
    if (profile == null) {
      await prefs.remove(_userProfileKey);
    } else {
      await prefs.setString(_userProfileKey, jsonEncode(profile));
    }
  }

  Future<Map<String, dynamic>?> loadAdminCredentials() async {
    return _loadSecureJson(_adminCredsKey);
  }

  Future<void> saveAdminCredentials(Map<String, dynamic>? creds) async {
    await _saveSecureJson(_adminCredsKey, creds);
  }

  Future<String?> loadAdminPinHash() async {
    final secure = await _secure.read(_adminPinKey);
    if (secure != null) return secure;
    // One-time migrate from plaintext SharedPreferences (pre–Phase 8).
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(_adminPinKey);
    if (legacy == null) return null;
    await _secure.write(_adminPinKey, legacy);
    await prefs.remove(_adminPinKey);
    return legacy;
  }

  Future<void> saveAdminPinHash(String? hash) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_adminPinKey);
    if (hash == null) {
      await _secure.delete(_adminPinKey);
    } else {
      await _secure.write(_adminPinKey, hash);
    }
  }

  Future<void> saveSpotifyPkce({required String verifier, required String state}) async {
    await _secure.write(
      _pkceKey,
      jsonEncode({'verifier': verifier, 'state': state}),
    );
    // Clear any pre–Phase 8 plaintext copy.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pkceKey);
  }

  Future<Map<String, String>?> loadSpotifyPkce() async {
    var raw = await _secure.read(_pkceKey);
    if (raw == null) {
      final prefs = await SharedPreferences.getInstance();
      raw = prefs.getString(_pkceKey);
      if (raw != null) {
        await _secure.write(_pkceKey, raw);
        await prefs.remove(_pkceKey);
      }
    }
    if (raw == null) return null;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return {
      'verifier': map['verifier'] as String,
      'state': map['state'] as String,
    };
  }

  Future<void> clearSpotifyPkce() async {
    await _secure.delete(_pkceKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pkceKey);
  }

  Future<Map<String, dynamic>?> _loadSecureJson(String key) async {
    var raw = await _secure.read(key);
    if (raw == null) {
      final prefs = await SharedPreferences.getInstance();
      raw = prefs.getString(key);
      if (raw != null) {
        await _secure.write(key, raw);
        await prefs.remove(key);
      }
    }
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> _saveSecureJson(String key, Map<String, dynamic>? value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
    if (value == null) {
      await _secure.delete(key);
    } else {
      await _secure.write(key, jsonEncode(value));
    }
  }
}
