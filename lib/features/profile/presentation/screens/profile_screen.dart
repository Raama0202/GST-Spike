import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gst_expense_scanner/core/theme/glass.dart';
import 'package:gst_expense_scanner/features/auth/presentation/providers/auth_providers.dart';
import 'package:gst_expense_scanner/features/company_config/presentation/company_config_providers.dart';
import 'package:gst_expense_scanner/features/sync/presentation/sync_providers.dart';
import 'package:gst_expense_scanner/shared/widgets/app_scaffold.dart';
import 'package:gst_expense_scanner/shared/widgets/primary_button.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final theme = Theme.of(context);

    if (auth is! AuthAuthenticated) {
      return AppScaffold(
        title: 'Profile',
        body: Center(
          child: PrimaryButton(
            label: 'Sign in',
            expand: false,
            onPressed: () => context.go('/login'),
          ),
        ),
      );
    }

    final employee = auth.employee;
    final config = ref.watch(activeCompanyConfigProvider);

    return AppScaffold(
      title: 'Profile',
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [theme.colorScheme.primary, Brand.violet],
                        ),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Text(
                        employee.name.isEmpty
                            ? '?'
                            : employee.name.characters.first.toUpperCase(),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(employee.name, style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    _infoRow('Mobile', '+91 ${employee.mobile}'),
                    if (employee.employeeCode != null)
                      _infoRow('Employee ID', employee.employeeCode!),
                    _infoRow(
                      'Company',
                      config?.companyName ?? employee.companyName,
                    ),
                    _infoRow('Branch', employee.branchName),
                  ],
                ),
              ),
            ),
            const Spacer(),
            PrimaryButton(
              label: 'Log out',
              icon: Icons.logout,
              onPressed: () async {
                ref.read(syncStatusProvider.notifier).stopEngine();
                await ref.read(authStateProvider.notifier).logout();
                if (context.mounted) context.go('/login');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
