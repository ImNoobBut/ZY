import 'package:flutter/foundation.dart';

/// Build-time / runtime configuration for Flutter (Android + Web).
class AppConfig {
  const AppConfig({
    required this.spotifyClientId,
    required this.spotifyRedirectUri,
    required this.backendBaseUrl,
    required this.androidApkUrl,
    required this.iosInstallUrl,
  });

  final String spotifyClientId;
  final String spotifyRedirectUri;
  final String backendBaseUrl;

  /// Absolute or site-relative URL for the Android APK (Cloudflare Pages).
  /// Override: `--dart-define=ANDROID_APK_URL=https://.../downloads/zy-sleep.apk`
  final String androidApkUrl;

  /// Absolute URL for iOS install (TestFlight / App Store / hosted IPA).
  /// Override: `--dart-define=IOS_INSTALL_URL=https://testflight.apple.com/join/...`
  final String iosInstallUrl;

  /// Public Pages origin used when building absolute download links on native.
  static const pagesOrigin = 'https://sleeping-routine-for-zy.pages.dev';

  /// Load from `--dart-define` / CI env.
  ///
  /// Spotify public client id has a project default (safe for PKCE; not a
  /// secret). Override with `--dart-define=SPOTIFY_CLIENT_ID=...` when needed.
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
      defaultValue: '8d55ca65ca71439597adb80e67ba2ab3',
    );
    const redirectDefine = String.fromEnvironment(
      'SPOTIFY_REDIRECT_URI',
      defaultValue: '',
    );
    const backend = String.fromEnvironment(
      'BACKEND_BASE_URL',
      defaultValue: 'http://localhost:8081',
    );
    const apkDefine = String.fromEnvironment('ANDROID_APK_URL', defaultValue: '');
    const iosDefine = String.fromEnvironment('IOS_INSTALL_URL', defaultValue: '');
    return AppConfig(
      spotifyClientId: clientId,
      spotifyRedirectUri: _resolveSpotifyRedirect(redirectDefine),
      backendBaseUrl: backend,
      androidApkUrl: apkDefine.isNotEmpty
          ? apkDefine
          : _defaultDownloadUrl('/downloads/zy-sleep.apk'),
      // Prefer an explicit TestFlight / App Store URL; bare .ipa is not installable
      // from Safari and often 404s when unpublished.
      iosInstallUrl: iosDefine,
    );
  }

  static String _defaultDownloadUrl(String path) {
    if (kIsWeb) {
      final origin = Uri.base.origin;
      final host = Uri.base.host.toLowerCase();
      final onLoopback = host == 'localhost' || host == '127.0.0.1';
      if (!onLoopback && origin.isNotEmpty && origin != 'null') {
        return '$origin$path';
      }
    }
    return '$pagesOrigin$path';
  }

  static String _resolveSpotifyRedirect(String redirectDefine) {
    if (!kIsWeb) {
      return redirectDefine.isNotEmpty
          ? redirectDefine
          : 'https://sleeping-routine-for-zy.pages.dev/callback';
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
