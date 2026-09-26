/// Platform-backed secret store for OAuth / device tokens and Admin PIN material.
///
/// - Android / iOS: Keystore / Keychain via `flutter_secure_storage`
/// - Web: encrypted-at-rest is not available in the browser; values still go
///   through this facade so secrets are not mixed with routine prefs, but they
///   remain readable to scripts on the same origin (honest web limitation).
abstract class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}
