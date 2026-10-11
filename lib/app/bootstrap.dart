import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'package:gst_expense_scanner/core/config/server_config.dart';
import 'package:gst_expense_scanner/core/di/providers.dart';
import 'package:gst_expense_scanner/core/services/notification_service.dart';
import 'package:gst_expense_scanner/features/auth/presentation/providers/auth_providers.dart';
import 'package:gst_expense_scanner/features/company_config/presentation/company_config_providers.dart';
import 'package:gst_expense_scanner/features/sync/data/background_sync_worker.dart';
import 'package:gst_expense_scanner/features/sync/presentation/sync_providers.dart';

/// Initializes platform services and restores the user session.
Future<void> bootstrap(ProviderContainer container) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Must precede any API client creation so the first request uses the
  // endpoint this device is actually configured for.
  await ServerConfig.load(container.read(secureStorageProvider));

  final database = container.read(localDatabaseProvider);
  await database.initialize();

  await NotificationService.instance.initialize();

  await Workmanager().initialize(backgroundSyncCallbackDispatcher);
  await BackgroundSyncWorker.registerPeriodic();

  await container.read(companyConfigStateProvider.notifier).loadCached();
  await container.read(authStateProvider.notifier).restore();

  final auth = container.read(authStateProvider);
  if (auth is AuthAuthenticated) {
    await container.read(syncStatusProvider.notifier).startEngine();
  }
}
