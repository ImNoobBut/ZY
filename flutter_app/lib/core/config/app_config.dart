import 'package:flutter/foundation.dart';

/// Build-time / runtime configuration for Flutter (Android + Web).
class AppConfig {
  const AppConfig({
    required this.spotifyClientId,
    required this.spotifyRedirectUri,
    required this.backendBaseUrl,
  });

  final String spotifyClientId;
  final String spotifyRedirectUri;
  final String backendBaseUrl;

  /// Load from `--dart-define` / CI env. No client IDs or prod URLs are baked in.
  ///
  /// Spotify Dashboard must list [spotifyRedirectUri] exactly
  /// (plus the iOS scheme `sleepingroutineforzy://spotify-callback`).
  ///
  /// On web, redirect is always `{current page origin}/callback` when the
  /// app is not on loopback. That prevents a stale local dart-define from
  /// breaking Cloudflare Pages OAuth.
  static AppConfig fromEnvironment() {
    const clientId = String.fromEnvironment(
      'SPOTIFY_CLIENT_ID',
      defaultValue: '',
    );
    const redirectDefine = String.fromEnvironment(
      'SPOTIFY_REDIRECT_URI',
      defaultValue: '',
    );
    const backend = String.fromEnvironment(
      'BACKEND_BASE_URL',
      defaultValue: 'http://localhost:8081',
    );
    return AppConfig(
      spotifyClientId: clientId,
      spotifyRedirectUri: _resolveSpotifyRedirect(redirectDefine),
      backendBaseUrl: backend,
    );
  }

  static String _resolveSpotifyRedirect(String redirectDefine) {
    if (!kIsWeb) {
      return redirectDefine.isNotEmpty
          ? redirectDefine
          : 'sleepingroutineforzy://spotify-callback';
    }

    final origin = Uri.base.origin;
    final host = Uri.base.host.toLowerCase();
    final onLoopback = host == 'localhost' || host == '127.0.0.1';

    // Production / Pages / any remote host: always match the live origin.
    if (!onLoopback && origin.isNotEmpty && origin != 'null') {
      return '$origin/callback';
    }

    if (redirectDefine.isNotEmpty) return redirectDefine;
    return '$origin/callback';
  }

  bool get hasSpotifyClientId => spotifyClientId.trim().isNotEmpty;
}
