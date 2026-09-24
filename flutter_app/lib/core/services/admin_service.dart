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
  String? accessToken;
  String? refreshToken;
  String? pairingCode;

  bool get isRegistered => deviceId != null && accessToken != null;

  Future<void> restore() async {
    final creds = await store.loadAdminCredentials();
    if (creds == null) return;
    deviceId = creds['deviceId'] as String?;
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
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    deviceId = json['deviceId'] as String;
    accessToken = json['accessToken'] as String;
    refreshToken = json['refreshToken'] as String;
    pairingCode = json['pairingCode'] as String;
    await store.saveAdminCredentials({
      'deviceId': deviceId,
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'pairingCode': pairingCode,
    });
  }

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

  Future<void> clear() async {
    deviceId = null;
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
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'pairingCode': pairingCode,
    });
  }
}
