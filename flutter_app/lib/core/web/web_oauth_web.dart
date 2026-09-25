import 'package:web/web.dart' as web;

/// Spotify redirect is registered for `127.0.0.1`, not `localhost`.
/// Those origins have separate localStorage, so PKCE is lost across a redirect
/// if the user opened the app via localhost. Force the canonical host.
///
/// Returns true if a navigation was triggered (caller should stop bootstrap).
bool canonicalizeWebHostToLoopback() {
  final uri = Uri.base;
  if (uri.host != 'localhost') return false;
  final next = uri.replace(host: '127.0.0.1');
  web.window.location.replace(next.toString());
  return true;
}

/// Drop `?code=` / `?error=` from the address bar after PKCE finishes so a
/// refresh does not replay the one-time auth code. Also leave `/callback`.
void clearOAuthCallbackFromBrowserUrl() {
  final uri = Uri.base;
  final hasOAuth = uri.queryParameters.containsKey('code') ||
      uri.queryParameters.containsKey('error') ||
      uri.queryParameters.containsKey('state');
  if (!hasOAuth && uri.path != '/callback') return;
  web.window.history.replaceState(null, '', '/');
}
