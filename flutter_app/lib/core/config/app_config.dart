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

  /// Defaults match local Windows demo. Override with --dart-define.
  ///
  /// Spotify Dashboard must list [spotifyRedirectUri] exactly
  /// (in addition to the iOS scheme `sleepingroutineforzy://spotify-callback`).
  static AppConfig fromEnvironment() {
    const clientId = String.fromEnvironment(
      'SPOTIFY_CLIENT_ID',
      defaultValue: '8d55ca65ca71439597adb80e67ba2ab3',
    );
    const redirect = String.fromEnvironment(
      'SPOTIFY_REDIRECT_URI',
      // Must match Spotify Developer Dashboard → Redirect URIs exactly.
      defaultValue: 'http://127.0.0.1:7357/callback',
    );
    const backend = String.fromEnvironment(
      'BACKEND_BASE_URL',
      defaultValue: 'http://localhost:8081',
    );
    return const AppConfig(
      spotifyClientId: clientId,
      spotifyRedirectUri: redirect,
      backendBaseUrl: backend,
    );
  }

  bool get hasSpotifyClientId => spotifyClientId.trim().isNotEmpty;
}
