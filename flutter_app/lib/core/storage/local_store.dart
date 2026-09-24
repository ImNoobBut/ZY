import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

class LocalStore {
  static const _prefsKey = 'user_preferences_v1';
  static const _routineKey = 'active_routine_v1';
  static const _alarmsKey = 'alarms_v1';
  static const _spotifyTokensKey = 'spotify_tokens_v1';
  static const _adminCredsKey = 'admin_creds_v1';
  static const _adminPinKey = 'admin_pin_hash_v1';

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
