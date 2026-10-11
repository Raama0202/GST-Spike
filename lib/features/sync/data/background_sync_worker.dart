import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/config/server_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../../core/storage/local_database.dart';
import '../../uploads/data/datasources/invoice_local_datasource.dart';
import '../../uploads/data/datasources/invoice_remote_datasource.dart';
import 'sync_engine.dart';

/// Background upload worker registration and execution.
class BackgroundSyncWorker {
  BackgroundSyncWorker._();

  static const taskName = 'gst_expense_background_sync';
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

    final secureStorage = SecureStorageService();
    // This runs in its own isolate, so the endpoint override has to be read
    // again; otherwise background uploads would go to the compiled-in server.
    await ServerConfig.load(secureStorage);

    final database = LocalDatabase(secureStorage);
    await database.initialize();

    final companyId = await secureStorage.companyId;
    if (companyId != null && companyId.isNotEmpty) {
      await database.openTenantBoxes(companyId);
    }

    final localDataSource = InvoiceLocalDataSource(database);
    final apiClient = ApiClient(
      secureStorage: secureStorage,
      onRefreshToken: () async => false,
    );
    final remoteDataSource = InvoiceRemoteDataSource(apiClient);
    final syncEngine = SyncEngine(
      localDataSource: localDataSource,
      remoteDataSource: remoteDataSource,
      connectivityService: ConnectivityService(),
    );

    await syncEngine.recoverQueue();
    await syncEngine.syncNow();
    return true;
  }
}

/// Workmanager entry point — must be a top-level function.
@pragma('vm:entry-point')
void backgroundSyncCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == BackgroundSyncWorker.taskName ||
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
