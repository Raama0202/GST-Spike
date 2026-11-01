import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/config/server_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../../core/services/isolate_guard.dart';
import '../../../core/storage/local_database.dart';
import '../../auth/data/datasources/auth_remote_datasource.dart';
import '../../uploads/data/datasources/invoice_local_datasource.dart';
import '../../uploads/data/datasources/invoice_remote_datasource.dart';
import 'sync_engine.dart';

/// Background upload worker registration and execution.
class BackgroundSyncWorker {
  BackgroundSyncWorker._();

  static const taskName = 'gst_expense_background_sync';

  /// Also the iOS BGTask identifier (AppDelegate.swift, Info.plist).
  static const uniqueName = 'gst_expense_sync_periodic';

  static Future<void> registerPeriodic() async {
    await Workmanager().registerPeriodicTask(
      uniqueName,
      taskName,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }

  static Future<void> registerOneOff() async {
    await Workmanager().registerOneOffTask(
      '${uniqueName}_once',
      taskName,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }

  static Future<bool> execute() async {
    WidgetsFlutterBinding.ensureInitialized();

    // The app's own sync engine is running and holds the Hive boxes; opening
    // them here as well could corrupt them.
    if (await IsolateGuard.foregroundActive()) return true;

    final secureStorage = SecureStorageService();
    if ((await secureStorage.refreshToken)?.isNotEmpty != true) return true;

    // This runs in its own isolate, so the endpoint override has to be read
    // again; otherwise background uploads would go to the compiled-in server.
    await ServerConfig.load(secureStorage);

    final database = LocalDatabase(secureStorage);
    try {
      await database.initialize();

      final companyId = await secureStorage.companyId;
      if (companyId != null && companyId.isNotEmpty) {
        await database.openTenantBoxes(companyId);
      }

      final authClient = ApiClient(
        secureStorage: secureStorage,
        onRefreshToken: () async => false,
      );
      final apiClient = ApiClient(
        secureStorage: secureStorage,
        onRefreshToken: () => _refreshTokens(secureStorage, authClient),
      );
      final syncEngine = SyncEngine(
        localDataSource: InvoiceLocalDataSource(database),
        remoteDataSource: InvoiceRemoteDataSource(apiClient),
        connectivityService: ConnectivityService(),
        imageStore: InvoiceImageStore(),
      );

      await syncEngine.recoverQueue();
      await syncEngine.syncNow();
      await IsolateGuard.markBackgroundRun();
      return true;
    } finally {
      await database.dispose();
    }
  }

  /// Rotates tokens without touching the session box; a rejected refresh
  /// token is left for the app to handle on next launch.
  static Future<bool> _refreshTokens(
    SecureStorageService storage,
    ApiClient authClient,
  ) async {
    final refresh = await storage.refreshToken;
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final tokens =
          await AuthRemoteDataSource(authClient).refreshToken(refresh);
      await storage.saveTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Workmanager entry point — must be a top-level function.
@pragma('vm:entry-point')
void backgroundSyncCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == BackgroundSyncWorker.taskName ||
        task == BackgroundSyncWorker.uniqueName ||
        task.startsWith(BackgroundSyncWorker.uniqueName)) {
      try {
        return await BackgroundSyncWorker.execute();
      } catch (_) {
        return false;
      }
    }
    return false;
  });
}
