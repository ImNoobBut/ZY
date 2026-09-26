import 'package:shared_preferences/shared_preferences.dart';

import 'secure_store.dart';

/// Web cannot offer a true Keychain. Prefixed SharedPreferences keeps secrets
/// out of the main LocalStore keys; treat the browser origin as the trust boundary.
SecureStore createSecureStore() => _WebSecureStore();

class _WebSecureStore implements SecureStore {
  static const _prefix = 'srz_secure_';

  @override
  Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefix$key');
  }

  @override
  Future<void> write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$key', value);
  }

  @override
  Future<void> delete(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$key');
  }
}
