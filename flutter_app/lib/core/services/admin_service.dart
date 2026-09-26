import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/models.dart';
import '../storage/local_store.dart';

class AdminService {
  AdminService({required this.config, required this.store});

  final AppConfig config;
  final LocalStore store;

  String? deviceId;
  String? accountId;
  String? accessToken;
  String? refreshToken;
  String? pairingCode;

  bool get isRegistered => deviceId != null && accessToken != null;

  Future<void> restore() async {
    final creds = await store.loadAdminCredentials();
    if (creds == null) return;
    deviceId = creds['deviceId'] as String?;
    accountId = creds['accountId'] as String?;
    accessToken = creds['accessToken'] as String?;
    refreshToken = creds['refreshToken'] as String?;
    pairingCode = creds['pairingCode'] as String?;
  }

  Future<void> register({String displayName = 'Zy Flutter'}) async {
    final res = await http.post(
      Uri.parse('${config.backendBaseUrl}/v1/devices/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'displayName': displayName}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Admin backend unavailable at ${config.backendBaseUrl}');
    }
    await _applyAuthResponse(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Join an existing sync account using another device's pairing code.
  Future<void> joinAccount({
    required String pairingCode,
    String displayName = 'Zy linked device',
  }) async {
    final res = await http.post(
      Uri.parse('${config.backendBaseUrl}/v1/devices/join'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'pairingCode': pairingCode,
        'displayName': displayName,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Could not join account (${res.statusCode}): ${res.body}');
    }
    await _applyAuthResponse(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> _applyAuthResponse(Map<String, dynamic> json) async {
    deviceId = json['deviceId'] as String;
    accountId = json['accountId'] as String?;
    accessToken = json['accessToken'] as String;
    refreshToken = json['refreshToken'] as String;
    pairingCode = json['pairingCode'] as String;
    await store.saveAdminCredentials({
      'deviceId': deviceId,
      'accountId': accountId,
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'pairingCode': pairingCode,
    });
  }

  /// Used by AuthService after email/password login or register.
  Future<void> applyAuthResponse(Map<String, dynamic> json) =>
      _applyAuthResponse(json);

  Future<void> checkIn(DeviceStatus status) async {
    if (!isRegistered) throw Exception('Device not registered');
    final res = await http.post(
      Uri.parse('${config.backendBaseUrl}/v1/devices/check-in'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'deviceStatus': status.toJson()}),
    );
    if (res.statusCode == 401 && refreshToken != null) {
      await _refresh();
      return checkIn(status);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Check-in failed (${res.statusCode})');
    }
  }

  /// Pending remote-admin commands for this device (unacked).
  Future<List<Map<String, dynamic>>> fetchPendingCommands() async {
    if (!isRegistered) return [];
    final res = await http.get(
      Uri.parse('${config.backendBaseUrl}/v1/devices/commands/pending'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (res.statusCode == 401 && refreshToken != null) {
      await _refresh();
      return fetchPendingCommands();
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Fetch commands failed (${res.statusCode})');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final list = json['commands'] as List<dynamic>? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> ackCommands(List<String> ids) async {
    if (!isRegistered || ids.isEmpty) return;
    final res = await http.post(
      Uri.parse('${config.backendBaseUrl}/v1/devices/commands/ack'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'ids': ids}),
    );
    if (res.statusCode == 401 && refreshToken != null) {
      await _refresh();
      return ackCommands(ids);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Ack commands failed (${res.statusCode})');
    }
  }

  /// Best-effort: revoke guardian admin tokens for this device.
  Future<void> revokeAdminTokens() async {
    if (!isRegistered) return;
    try {
      final res = await http.post(
        Uri.parse('${config.backendBaseUrl}/v1/devices/revoke-admin-tokens'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (res.statusCode == 401 && refreshToken != null) {
        await _refresh();
        final retry = await http.post(
          Uri.parse('${config.backendBaseUrl}/v1/devices/revoke-admin-tokens'),
          headers: {'Authorization': 'Bearer $accessToken'},
        );
        if (retry.statusCode < 200 || retry.statusCode >= 300) return;
      }
    } catch (_) {
      // Disconnect must still clear local state if the network is down.
    }
  }

  Future<void> clear() async {
    deviceId = null;
    accountId = null;
    accessToken = null;
    refreshToken = null;
    pairingCode = null;
    await store.saveAdminCredentials(null);
  }

  Future<void> _refresh() async {
    final res = await http.post(
      Uri.parse('${config.backendBaseUrl}/v1/devices/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refreshToken': refreshToken}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Token refresh failed');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    accessToken = json['accessToken'] as String;
    refreshToken = (json['refreshToken'] as String?) ?? refreshToken;
    await store.saveAdminCredentials({
      'deviceId': deviceId,
      'accountId': accountId,
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'pairingCode': pairingCode,
    });
  }

  /// Exposed for SyncService token refresh.
  Future<void> refreshTokens() => _refresh();
}
