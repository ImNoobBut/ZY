import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_store.dart';

SecureStore createSecureStore() => _IoSecureStore();

class _IoSecureStore implements SecureStore {
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
