import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorage {
  static const _tokenKey = 'groots_access_token';

  final FlutterSecureStorage _storage;

  SecureStorage()
    : _storage = const FlutterSecureStorage(
        // useDataProtectionKeychain requires keychain-access-groups entitlement
        // and a signing certificate. The legacy keychain works without either.
        mOptions: MacOsOptions(useDataProtectionKeyChain: false),
      );

  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);
  Future<String?> getToken() => _storage.read(key: _tokenKey);
  Future<void> deleteToken() => _storage.delete(key: _tokenKey);
}
