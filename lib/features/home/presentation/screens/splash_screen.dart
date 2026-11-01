import 'package:flutter/material.dart';

import 'package:gst_expense_scanner/core/constants/app_constants.dart';
import 'package:gst_expense_scanner/core/theme/glass.dart';

/// Shown only while bootstrap's session restore is still running; the router
/// leaves this screen as soon as the auth state settles.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

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
