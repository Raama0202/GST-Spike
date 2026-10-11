import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  SecureStore(this._storage);
  final FlutterSecureStorage _storage;

  static const _tokenKey = 'admin_access_token';
  static const _refreshKey = 'admin_refresh_token';
  static const _roleKey = 'admin_role';
  static const _companyKey = 'admin_company_id';
  static const _nameKey = 'admin_display_name';
  static const _apiOverrideKey = 'admin_api_base_url_override';

  Future<String?> get token => _storage.read(key: _tokenKey);
  Future<String?> get refreshToken => _storage.read(key: _refreshKey);
  Future<String?> get role => _storage.read(key: _roleKey);
  Future<String?> get companyId => _storage.read(key: _companyKey);
  Future<String?> get displayName => _storage.read(key: _nameKey);
  Future<String?> get apiBaseUrlOverride => _storage.read(key: _apiOverrideKey);

  Future<void> setApiBaseUrlOverride(String value) =>
      _storage.write(key: _apiOverrideKey, value: value);

  Future<void> clearApiBaseUrlOverride() =>
      _storage.delete(key: _apiOverrideKey);

  Future<void> saveSession({
    required String token,
    required String role,
    String? refreshToken,
    String? companyId,
    String? displayName,
  }) async {
    // Sequential: on web, concurrent first writes each generate a different
    // encryption key and earlier values become undecryptable.
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _refreshKey, value: refreshToken);
    await _storage.write(key: _roleKey, value: role);
    await _storage.write(key: _companyKey, value: companyId);
    await _storage.write(key: _nameKey, value: displayName);
  }

  Future<void> saveTokens(String token, String? refreshToken) async {
    await _storage.write(key: _tokenKey, value: token);
    if (refreshToken != null) {
      await _storage.write(key: _refreshKey, value: refreshToken);
    }
  }

  /// Signs out but keeps the server override so the next login hits the same API.
  Future<void> clear() async {
    for (final key in [
      _tokenKey,
      _refreshKey,
      _roleKey,
      _companyKey,
      _nameKey,
    ]) {
      await _storage.delete(key: key);
    }
  }
}
