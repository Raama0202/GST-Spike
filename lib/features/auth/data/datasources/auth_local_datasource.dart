import 'package:jwt_decoder/jwt_decoder.dart';

import 'package:gst_expense_scanner/core/constants/app_constants.dart';
import 'package:gst_expense_scanner/core/security/secure_storage_service.dart';
import 'package:gst_expense_scanner/core/storage/local_database.dart';
import 'package:gst_expense_scanner/shared/models/employee_entity.dart';

class AuthLocalDataSource {
  AuthLocalDataSource({
    required LocalDatabase database,
    required SecureStorageService secureStorage,
  }) : _database = database,
       _secureStorage = secureStorage;

  static const String _employeeKey = 'employee';

  final LocalDatabase _database;
  final SecureStorageService _secureStorage;

  Future<String> deviceId() => _secureStorage.getOrCreateDeviceId();

  Future<void> saveSession({
    required AuthTokens tokens,
    required EmployeeEntity employee,
  }) async {
    await _secureStorage.saveTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
    await _secureStorage.setCompanyId(employee.companyId);
    await _secureStorage.setEmployeeId(employee.id);
    await _database.session.put(_employeeKey, employee.toJson());
  }

  Future<EmployeeEntity?> readSession() async {
    final raw = _database.session.get(_employeeKey);
    if (raw == null) return null;
    if (raw is! Map) return null;
    return EmployeeEntity.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<void> clearSession() async {
    await _database.session.delete(_employeeKey);
    await _secureStorage.clearSession();
  }

  /// Fast local hint — does not call the network.
  Future<bool> hasValidSession() async {
    final remember = await _secureStorage.rememberLogin;
    if (!remember) return false;

    final refresh = await _secureStorage.refreshToken;
    if (refresh == null || refresh.isEmpty) return false;

    final access = await _secureStorage.accessToken;
    if (access == null || access.isEmpty) {
      return refresh.isNotEmpty;
    }

    try {
      if (JwtDecoder.isExpired(access)) {
        return refresh.isNotEmpty;
      }
      final expiry = JwtDecoder.getExpirationDate(access);
      return expiry.isAfter(DateTime.now().add(AppConstants.tokenRefreshSkew));
    } catch (_) {
      return true;
    }
  }

  Future<bool> get rememberLogin => _secureStorage.rememberLogin;

  Future<void> setRememberLogin(bool value) =>
      _secureStorage.setRememberLogin(value);

  Future<AuthTokens?> readTokens() async {
    final access = await _secureStorage.accessToken;
    final refresh = await _secureStorage.refreshToken;
    if (access == null ||
        refresh == null ||
        access.isEmpty ||
        refresh.isEmpty) {
      return null;
    }
    return AuthTokens(accessToken: access, refreshToken: refresh);
  }
}
