import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gst_expense_scanner/core/constants/app_constants.dart';
import 'package:gst_expense_scanner/core/services/notification_service.dart';
import 'package:gst_expense_scanner/core/theme/glass.dart';
import 'package:gst_expense_scanner/features/auth/presentation/providers/auth_providers.dart';
import 'package:gst_expense_scanner/features/company_config/presentation/company_config_providers.dart';
import 'package:gst_expense_scanner/features/sync/presentation/sync_providers.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await ref.read(companyConfigStateProvider.notifier).loadCached();

    final auth = ref.read(authStateProvider);
    if (auth is! AuthAuthenticated) {
      await ref.read(authStateProvider.notifier).restore();
    }

    if (!mounted) return;

    final restored = ref.read(authStateProvider);
    if (restored is AuthAuthenticated) {
      await ref.read(syncStatusProvider.notifier).startEngine();
    }

    if (!mounted) return;

    final finalAuth = ref.read(authStateProvider);
    if (finalAuth is AuthAuthenticated) {
      context.go('/home');
      unawaited(NotificationService.instance.requestPermission());
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconBadge(
              icon: Icons.receipt_long_rounded,
              color: theme.colorScheme.primary,
              size: 88,
            ),
            const SizedBox(height: 24),
            Text(AppConstants.appName, style: theme.textTheme.headlineMedium),
            const SizedBox(height: 32),
            const SizedBox(
              height: 32,
              width: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 16),
            Text(
              'Restoring session…',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
