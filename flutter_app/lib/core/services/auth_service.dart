import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../storage/local_store.dart';
import 'admin_service.dart';

class UserProfile {
  const UserProfile({
    required this.email,
    required this.displayName,
    this.accountId,
  });

  final String email;
  final String displayName;
  final String? accountId;

  Map<String, dynamic> toJson() => {
        'email': email,
        'displayName': displayName,
        if (accountId != null) 'accountId': accountId,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      email: (json['email'] as String?)?.trim() ?? '',
      displayName: (json['displayName'] as String?)?.trim() ?? '',
      accountId: json['accountId'] as String?,
    );
  }
}

class AuthService {
  AuthService({
    required this.config,
    required this.store,
    required this.admin,
  });

  final AppConfig config;
  final LocalStore store;
  final AdminService admin;

  UserProfile? profile;

  bool get isLoggedIn =>
      profile != null &&
      profile!.email.isNotEmpty &&
      admin.isRegistered;

  Future<void> restore() async {
    final raw = await store.loadUserProfile();
    if (raw == null) {
      profile = null;
      return;
    }
    profile = UserProfile.fromJson(raw);
  }

  String get _deviceDisplayName => kIsWeb ? 'Zy Web' : 'Zy Flutter';

  Future<UserProfile> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final res = await http.post(
      Uri.parse('${config.backendBaseUrl}/v1/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
        'displayName': displayName.trim(),
        'deviceDisplayName': _deviceDisplayName,
      }),
    );
    if (res.statusCode == 409) {
      throw Exception('That email is already registered. Try signing in.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(_errorDetail(res) ?? 'Could not register (${res.statusCode})');
    }
    return _applyAuthResponse(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<UserProfile> login({
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('${config.backendBaseUrl}/v1/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
        'deviceDisplayName': _deviceDisplayName,
      }),
    );
    if (res.statusCode == 401) {
      throw Exception('Invalid email or password.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(_errorDetail(res) ?? 'Could not sign in (${res.statusCode})');
    }
    return _applyAuthResponse(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<UserProfile> updateDisplayName(String displayName) async {
    if (!admin.isRegistered) {
      throw Exception('Not signed in');
    }
    final trimmed = displayName.trim();
    final res = await http.patch(
      Uri.parse('${config.backendBaseUrl}/v1/auth/me'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${admin.accessToken}',
      },
      body: jsonEncode({'displayName': trimmed}),
    );
    if (res.statusCode == 401 && admin.refreshToken != null) {
      await admin.refreshTokens();
      return updateDisplayName(trimmed);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(_errorDetail(res) ?? 'Could not update name (${res.statusCode})');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    profile = UserProfile(
      email: (json['email'] as String?) ?? profile?.email ?? '',
      displayName: (json['displayName'] as String?)?.trim() ?? trimmed,
      accountId: (json['accountId'] as String?) ?? profile?.accountId,
    );
    await store.saveUserProfile(profile!.toJson());
    return profile!;
  }

  Future<void> signOut() async {
    profile = null;
    await store.saveUserProfile(null);
    await admin.clear();
    await store.saveSyncCursor(null);
    await store.saveLastSyncIso(null);
    await store.saveOutbox([]);
  }

  Future<UserProfile> _applyAuthResponse(Map<String, dynamic> json) async {
    await admin.applyAuthResponse(json);
    final next = UserProfile(
      email: (json['email'] as String?)?.trim() ?? '',
      displayName: (json['displayName'] as String?)?.trim() ?? '',
      accountId: json['accountId'] as String?,
    );
    if (next.email.isEmpty) {
      throw Exception('Auth response missing email');
    }
    profile = next;
    await store.saveUserProfile(next.toJson());
    return next;
  }

  static String? _errorDetail(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['detail'] is String) {
        return body['detail'] as String;
      }
    } catch (_) {}
    return null;
  }
}
