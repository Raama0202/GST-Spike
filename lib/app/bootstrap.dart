import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'package:gst_expense_scanner/app/router.dart';
import 'package:gst_expense_scanner/core/config/server_config.dart';
import 'package:gst_expense_scanner/core/services/crash_reporter.dart';
import 'package:gst_expense_scanner/core/services/notification_service.dart';
import 'package:gst_expense_scanner/core/services/push_service.dart';
import 'package:gst_expense_scanner/features/auth/presentation/providers/auth_providers.dart';
import 'package:gst_expense_scanner/features/company_config/presentation/company_config_providers.dart';
import 'package:gst_expense_scanner/features/notifications/presentation/notification_providers.dart';
import 'package:gst_expense_scanner/features/sync/data/background_sync_worker.dart';
import 'package:gst_expense_scanner/features/sync/presentation/sync_providers.dart';

/// Work that must finish before the first frame: local storage only, so a
/// slow or cold server can never hold the user on the native splash.
Future<void> bootstrap(ProviderContainer container) async {
  // Must precede any API client creation so the first request uses the
  // endpoint this device is actually configured for.
  await ServerConfig.load(container.read(secureStorageProvider));

  await container.read(localDatabaseProvider).initialize();
  await container.read(companyConfigStateProvider.notifier).loadCached();

  try {
    await container
        .read(authStateProvider.notifier)
        .restore()
        .timeout(const Duration(seconds: 8));
  } on TimeoutException {
    // Restore keeps running; the splash screen waits for its result.
  }
}

/// Platform services and background work, started after the first frame.
Future<void> startServices(ProviderContainer container) async {
  container.listen<AuthState>(authStateProvider, (previous, next) {
    final sync = container.read(syncStatusProvider.notifier);
    if (next is AuthAuthenticated) {
      unawaited(sync.startEngine());
    } else if (next is AuthUnauthenticated || next is AuthErrorState) {
      sync.stopEngine();
    }
  }, fireImmediately: true);

  final router = container.read(routerProvider);
  void openFromNotification(String? invoiceServerId) {
    if (container.read(authStateProvider) is! AuthAuthenticated) return;
    if (invoiceServerId != null && invoiceServerId.isNotEmpty) {
      unawaited(router.push('/uploads/server/$invoiceServerId'));
    } else {
      unawaited(router.push('/notifications'));
    }
  }

  NotificationService.instance.onTap = openFromNotification;
  await _guard('notifications', NotificationService.instance.initialize);

  final push = PushService.instance
    ..onMessage = (() => container.invalidate(notificationsListProvider))
    ..onOpened = ((data) =>
        openFromNotification(data['invoiceServerId']?.toString()));
  await _guard('push', push.initialize);

  await _guard('workmanager', () async {
    await Workmanager().initialize(backgroundSyncCallbackDispatcher);
    await BackgroundSyncWorker.registerPeriodic();
  });

  if (container.read(authStateProvider) is AuthAuthenticated) {
    final pushLaunch = push.takeLaunchMessage();
    final localLaunch = await NotificationService.instance.launchPayload();
    if (pushLaunch != null || localLaunch != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        openFromNotification(
          pushLaunch?['invoiceServerId']?.toString() ?? localLaunch,
        );
      });
    }
    unawaited(NotificationService.instance.requestPermission());
  }
}

Future<void> _guard(String name, Future<void> Function() action) async {
  try {
    await action();
  } catch (error, stack) {
    CrashReporter.record(error, stack, reason: 'startup $name');
  }
}

/// Shown when local storage cannot be opened, instead of a blank screen.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.error_outline_rounded, size: 56),
                const SizedBox(height: 16),
                const Text(
                  'The app could not start',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Close the app completely and open it again. If this keeps '
                  'happening, contact your administrator.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
