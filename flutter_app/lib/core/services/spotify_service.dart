import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../storage/local_store.dart';

class SpotifyService {
  SpotifyService({required this.config, required this.store});

  final AppConfig config;
  final LocalStore store;

  bool get isAuthenticated => _accessToken != null;
  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiry;
  String? _pendingVerifier;
  String? _pendingState;

  Future<void> restore() async {
    final tokens = await store.loadSpotifyTokens();
    if (tokens == null) return;
    _accessToken = tokens['accessToken'] as String?;
    _refreshToken = tokens['refreshToken'] as String?;
    final expiry = tokens['expiry'] as String?;
    _expiry = expiry != null ? DateTime.tryParse(expiry) : null;
  }

  Future<Uri> buildAuthorizeUri() async {
    if (!config.hasSpotifyClientId) {
      throw Exception('Add SPOTIFY_CLIENT_ID via --dart-define');
    }
    _pendingVerifier = _makeVerifier();
    _pendingState = _uuidLike();
    await store.saveSpotifyPkce(verifier: _pendingVerifier!, state: _pendingState!);
    final challenge = _makeChallenge(_pendingVerifier!);
    final uri = Uri.https('accounts.spotify.com', '/authorize', {
      'client_id': config.spotifyClientId,
      'response_type': 'code',
      'redirect_uri': config.spotifyRedirectUri,
      'scope':
          'user-read-private playlist-read-private playlist-read-collaborative user-modify-playback-state user-read-playback-state',
      'code_challenge_method': 'S256',
      'code_challenge': challenge,
      'state': _pendingState,
    });
    return uri;
  }

  Future<void> openAuthorizeInBrowser() async {
    final uri = await buildAuthorizeUri();
    // On web, stay in the same tab so Spotify can redirect back to /callback.
    // On Android, open the system browser; HTTPS App Links return via app_links.
    final ok = await launchUrl(
      uri,
      webOnlyWindowName: '_self',
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
    if (!ok) throw Exception('Could not open Spotify login');
  }

  /// If the browser landed on our redirect URI with ?code=, finish PKCE exchange.
  Future<bool> tryCompleteFromCurrentUri(Uri current) async {
    final oauthError = current.queryParameters['error'];
    if (oauthError != null) {
      final desc = current.queryParameters['error_description'] ?? oauthError;
      await store.clearSpotifyPkce();
      throw Exception('Spotify login cancelled or denied: $desc');
    }

    final code = current.queryParameters['code'];
    final state = current.queryParameters['state'];
    if (code == null || state == null) return false;

    final saved = await store.loadSpotifyPkce();
    final verifier = saved?['verifier'] ?? _pendingVerifier;
    final expectedState = saved?['state'] ?? _pendingState;
    if (verifier == null || expectedState == null) {
      throw Exception(
        'Spotify login expired (missing PKCE). '
        'Open the app at ${config.spotifyRedirectUri.replaceAll('/callback', '')} '
        '(use 127.0.0.1, not localhost), then Connect Spotify again.',
      );
    }
    if (state != expectedState) {
      await store.clearSpotifyPkce();
      throw Exception('Spotify login expired (state mismatch). Tap Connect Spotify again.');
    }
    _pendingVerifier = verifier;
    _pendingState = expectedState;
    await completeAuthFromRedirect(current);
    return true;
  }

  /// Complete OAuth after redirect lands with ?code=&state=
  Future<void> completeAuthFromRedirect(Uri redirect) async {
    final code = redirect.queryParameters['code'];
    final state = redirect.queryParameters['state'];
    final saved = await store.loadSpotifyPkce();
    final verifier = saved?['verifier'] ?? _pendingVerifier;
    final expectedState = saved?['state'] ?? _pendingState;
    if (code == null ||
        state == null ||
        verifier == null ||
        expectedState == null ||
        state != expectedState) {
      throw Exception('Invalid Spotify callback');
    }
    final body = {
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': config.spotifyRedirectUri,
      'client_id': config.spotifyClientId,
      'code_verifier': verifier,
    };
    final res = await http.post(
      Uri.parse('https://accounts.spotify.com/api/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Spotify token exchange failed (${res.statusCode}): ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    await _applyTokenResponse(json);
    await store.clearSpotifyPkce();
  }

  /// Demo connect for Windows testing without completing browser redirect.
  Future<void> connectDemo() async {
    _accessToken = 'demo-token';
    _refreshToken = 'demo-refresh';
    _expiry = DateTime.now().add(const Duration(hours: 1));
    await store.saveSpotifyTokens({
      'accessToken': _accessToken,
      'refreshToken': _refreshToken,
      'expiry': _expiry!.toIso8601String(),
      'demo': true,
    });
  }

  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    _expiry = null;
    await store.saveSpotifyTokens(null);
  }

  Future<List<SpotifyPlaylist>> getPlaylists() async {
    if (_isDemo) {
      return [
        SpotifyPlaylist(
          id: 'demo',
          name: 'Sleep Playlist',
          uri: 'spotify:playlist:demo',
          trackCount: 12,
        ),
      ];
    }
    await _ensureToken();
    final res = await http.get(
      Uri.parse('https://api.spotify.com/v1/me/playlists?limit=50'),
      headers: {'Authorization': 'Bearer $_accessToken'},
    );
    if (res.statusCode != 200) throw Exception('Failed to load playlists');
    final items = (jsonDecode(res.body)['items'] as List?) ?? [];
    return items.map((item) {
      final map = item as Map<String, dynamic>;
      return SpotifyPlaylist(
        id: map['id'] as String,
        name: map['name'] as String? ?? 'Playlist',
        uri: map['uri'] as String,
        trackCount: (map['tracks'] as Map?)?['total'] as int? ?? 0,
      );
    }).toList();
  }

  Future<List<SpotifyTrack>> search(String query) async {
    if (_isDemo) {
      return [
        SpotifyTrack(
          id: '1',
          name: 'Quiet Evening',
          artistName: 'Demo',
          uri: 'spotify:track:demo1',
        ),
      ];
    }
    await _ensureToken();
    final uri = Uri.https('api.spotify.com', '/v1/search', {
      'q': query,
      'type': 'track',
      'limit': '20',
    });
    final res = await http.get(uri, headers: {'Authorization': 'Bearer $_accessToken'});
    if (res.statusCode != 200) throw Exception('Search failed');
    final items = (jsonDecode(res.body)['tracks']?['items'] as List?) ?? [];
    return items.map((item) {
      final map = item as Map<String, dynamic>;
      final artists = (map['artists'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      return SpotifyTrack(
        id: map['id'] as String,
        name: map['name'] as String? ?? 'Track',
        artistName: artists.map((a) => a['name']).join(', '),
        uri: map['uri'] as String,
      );
    }).toList();
  }

  Future<void> play(String spotifyUri) async {
    if (_isDemo) return;
    await _ensureToken();
    final body = spotifyUri.contains(':track:')
        ? {'uris': [spotifyUri]}
        : {'context_uri': spotifyUri};

    Future<http.Response> sendPlay({String? deviceId}) {
      final uri = deviceId == null
          ? Uri.parse('https://api.spotify.com/v1/me/player/play')
          : Uri.parse('https://api.spotify.com/v1/me/player/play?device_id=$deviceId');
      return http.put(
        uri,
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
    }

    var res = await sendPlay();
    if (res.statusCode == 404) {
      final deviceId = await _firstAvailableDeviceId();
      if (deviceId != null) {
        await _transferPlayback(deviceId);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        res = await sendPlay(deviceId: deviceId);
      }
    }
    if (res.statusCode == 404 || res.statusCode == 403) {
      throw Exception(
        'No active Spotify device. Open Spotify on your phone or desktop, '
        'play any track once, then retry. Premium is required for remote play.',
      );
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Playback request failed (${res.statusCode}): ${res.body}');
    }
  }

  /// Visible Connect targets (empty until Spotify is open somewhere).
  Future<List<String>> listDeviceNames() async {
    if (_isDemo) return ['Demo device'];
    await _ensureToken();
    final res = await http.get(
      Uri.parse('https://api.spotify.com/v1/me/player/devices'),
      headers: {'Authorization': 'Bearer $_accessToken'},
    );
    if (res.statusCode != 200) return [];
    final devices = (jsonDecode(res.body)['devices'] as List?) ?? [];
    return devices.map((raw) {
      final map = raw as Map<String, dynamic>;
      final name = map['name'] as String? ?? 'Device';
      final type = map['type'] as String? ?? '';
      final active = map['is_active'] == true ? ' (active)' : '';
      return type.isEmpty ? '$name$active' : '$name · $type$active';
    }).toList();
  }

  Future<void> openSpotifyApp() async {
    final uri = Uri.parse('https://open.spotify.com/');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<String?> _firstAvailableDeviceId() async {
    final res = await http.get(
      Uri.parse('https://api.spotify.com/v1/me/player/devices'),
      headers: {'Authorization': 'Bearer $_accessToken'},
    );
    if (res.statusCode != 200) return null;
    final devices = (jsonDecode(res.body)['devices'] as List?) ?? [];
    String? fallback;
    for (final raw in devices) {
      final map = raw as Map<String, dynamic>;
      final id = map['id'] as String?;
      if (id == null || id.isEmpty) continue;
      if (map['is_active'] == true) return id;
      fallback ??= id;
    }
    return fallback;
  }

  Future<void> _transferPlayback(String deviceId) async {
    await http.put(
      Uri.parse('https://api.spotify.com/v1/me/player'),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'device_ids': [deviceId],
        'play': false,
      }),
    );
  }

  Future<void> pause() async {
    if (_isDemo) return;
    if (_accessToken == null) return;
    try {
      await _ensureToken();
    } catch (_) {
      return;
    }
    await http.put(
      Uri.parse('https://api.spotify.com/v1/me/player/pause'),
      headers: {'Authorization': 'Bearer $_accessToken'},
    );
  }

  bool get _isDemo => _accessToken == 'demo-token';

  Future<void> _ensureToken() async {
    if (_accessToken == null) throw Exception('Spotify not connected');
    if (_expiry != null && DateTime.now().isBefore(_expiry!.subtract(const Duration(seconds: 60)))) {
      return;
    }
    if (_isDemo) return;
    if (_refreshToken == null) {
      await logout();
      throw Exception('Spotify session expired. Connect Spotify again.');
    }
    final res = await http.post(
      Uri.parse('https://accounts.spotify.com/api/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': _refreshToken!,
        'client_id': config.spotifyClientId,
      },
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      await _applyTokenResponse(jsonDecode(res.body) as Map<String, dynamic>);
      return;
    }
    await logout();
    throw Exception(
      'Spotify session expired (${res.statusCode}). Connect Spotify again.',
    );
  }

  Future<void> _applyTokenResponse(Map<String, dynamic> json) async {
    _accessToken = json['access_token'] as String;
    _refreshToken = (json['refresh_token'] as String?) ?? _refreshToken;
    final expiresIn = json['expires_in'] as int? ?? 3600;
    _expiry = DateTime.now().add(Duration(seconds: expiresIn));
    await store.saveSpotifyTokens({
      'accessToken': _accessToken,
      'refreshToken': _refreshToken,
      'expiry': _expiry!.toIso8601String(),
    });
  }

  String _makeVerifier() {
    const alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    final rand = Random.secure();
    return List.generate(64, (_) => alphabet[rand.nextInt(alphabet.length)]).join();
  }

  String _makeChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  String _uuidLike() => List.generate(16, (_) => Random.secure().nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}
