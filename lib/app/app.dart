import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gst_expense_scanner/core/constants/app_constants.dart';
import 'package:gst_expense_scanner/core/di/providers.dart';
import 'package:gst_expense_scanner/core/services/isolate_guard.dart';
import 'package:gst_expense_scanner/core/theme/app_theme.dart';
import 'package:gst_expense_scanner/features/auth/presentation/providers/auth_providers.dart';
import 'package:gst_expense_scanner/features/company_config/presentation/company_config_providers.dart';
import 'package:gst_expense_scanner/features/sync/presentation/sync_providers.dart';

import 'router.dart';

class GstExpenseApp extends ConsumerStatefulWidget {
  const GstExpenseApp({super.key});

  @override
  ConsumerState<GstExpenseApp> createState() => _GstExpenseAppState();
}

class _GstExpenseAppState extends ConsumerState<GstExpenseApp>
    with WidgetsBindingObserver {
  static const _configRefreshInterval = Duration(minutes: 30);
  static const _configMinAge = Duration(minutes: 5);

  Timer? _heartbeat;
  Timer? _configTimer;
  DateTime _configFetchedAt = DateTime.now();
  int? _seenBackgroundRun;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(IsolateGuard.beat());
    _heartbeat = Timer.periodic(
      IsolateGuard.heartbeatInterval,
      (_) => unawaited(IsolateGuard.beat()),
    );
    _configTimer = Timer.periodic(_configRefreshInterval, (_) {
      if (ref.read(appLifecycleProvider) == AppLifecycleState.resumed) {
        unawaited(_refreshConfig());
      }
    });
    unawaited(
      IsolateGuard.lastBackgroundRun().then((v) => _seenBackgroundRun = v),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeat?.cancel();
    _configTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(appLifecycleProvider.notifier).state = state;
    if (state == AppLifecycleState.resumed) unawaited(_onResumed());
  }

  Future<void> _onResumed() async {
    await IsolateGuard.beat();
    if (ref.read(authStateProvider) is! AuthAuthenticated) return;

    // The background worker may have uploaded while the app was frozen; its
    // writes are on disk but not in this isolate's in-memory boxes.
    final backgroundRun = await IsolateGuard.lastBackgroundRun();
    if (backgroundRun != null && backgroundRun != _seenBackgroundRun) {
      _seenBackgroundRun = backgroundRun;
      try {
        await ref.read(localDatabaseProvider).reloadTenantBoxes();
        ref.read(syncStatusProvider.notifier).markChanged();
      } catch (_) {}
    }

    ref.read(syncStatusProvider.notifier).nudge();
    if (DateTime.now().difference(_configFetchedAt) >= _configMinAge) {
      await _refreshConfig();
    }
  }

  Future<void> _refreshConfig() async {
    _configFetchedAt = DateTime.now();
    await ref.read(authStateProvider.notifier).refreshCompanyConfig();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final brandColor = ref.watch(companyBrandColorProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(brandPrimary: brandColor),
      darkTheme: AppTheme.dark(brandPrimary: brandColor),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
