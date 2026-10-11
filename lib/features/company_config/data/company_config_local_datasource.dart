import 'package:gst_expense_scanner/core/constants/app_constants.dart';
import 'package:gst_expense_scanner/core/security/secure_storage_service.dart';
import 'package:gst_expense_scanner/core/storage/local_database.dart';
import 'package:gst_expense_scanner/shared/models/company_config.dart';

class CompanyConfigLocalDataSource {
  CompanyConfigLocalDataSource({
    required LocalDatabase database,
    required SecureStorageService secureStorage,
  })  : _database = database,
        _secureStorage = secureStorage;

  static const String _configKey = 'config';

  final LocalDatabase _database;
  final SecureStorageService _secureStorage;

  Future<void> saveConfig(CompanyConfig config) async {
    await _database.companyConfig.put(_configKey, config.toJson());
    await _secureStorage.write(
      StorageKeys.lastConfigSyncAt,
      DateTime.now().toIso8601String(),
    );
  }

  CompanyConfig? readConfig() {
    final raw = _database.companyConfig.get(_configKey);
    if (raw == null || raw is! Map) return null;
    return CompanyConfig.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<void> clearConfig() async {
    await _database.companyConfig.delete(_configKey);
    await _secureStorage.delete(StorageKeys.lastConfigSyncAt);
  }

  Future<DateTime?> lastSyncedAt() async {
    final raw = await _secureStorage.read(StorageKeys.lastConfigSyncAt);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}
