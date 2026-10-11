import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';

/// Encrypted key-value store for tokens and encryption keys.
class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;
  final _uuid = const Uuid();

  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> delete(String key) => _storage.delete(key: key);

  Future<void> clearSession() async {
    await Future.wait([
      delete(StorageKeys.accessToken),
      delete(StorageKeys.refreshToken),
      delete(StorageKeys.companyId),
      delete(StorageKeys.employeeId),
    ]);
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await write(StorageKeys.accessToken, accessToken);
    await write(StorageKeys.refreshToken, refreshToken);
  }

  Future<String?> get accessToken => read(StorageKeys.accessToken);
  Future<String?> get refreshToken => read(StorageKeys.refreshToken);

  Future<void> setCompanyId(String id) => write(StorageKeys.companyId, id);
  Future<String?> get companyId => read(StorageKeys.companyId);

  Future<void> setEmployeeId(String id) => write(StorageKeys.employeeId, id);
  Future<String?> get employeeId => read(StorageKeys.employeeId);

  Future<void> setRememberLogin(bool value) =>
      write(StorageKeys.rememberLogin, value ? '1' : '0');

  Future<bool> get rememberLogin async =>
      (await read(StorageKeys.rememberLogin)) == '1';

  Future<String> getOrCreateDeviceId() async {
    final existing = await read(StorageKeys.deviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _uuid.v4();
    await write(StorageKeys.deviceId, id);
    return id;
  }

  /// 32-byte Hive AES key, persisted across restarts.
  Future<Uint8List> getOrCreateHiveKey() async {
    final existing = await read(StorageKeys.hiveEncryptionKey);
    if (existing != null && existing.isNotEmpty) {
      return Uint8List.fromList(base64Decode(existing));
    }
    final secure = _secureRandomBytes(32);
    await write(StorageKeys.hiveEncryptionKey, base64Encode(secure));
    return secure;
  }

  Uint8List _secureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
