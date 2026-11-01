import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:gst_expense_scanner/core/constants/env_config.dart';
import 'package:gst_expense_scanner/core/theme/glass.dart';
import 'package:gst_expense_scanner/core/utils/mobile_number.dart';
import 'package:gst_expense_scanner/features/auth/presentation/providers/auth_providers.dart';
import 'package:gst_expense_scanner/features/company_config/presentation/company_config_providers.dart';
import 'package:gst_expense_scanner/features/home/presentation/providers/home_providers.dart';
import 'package:gst_expense_scanner/features/sync/presentation/sync_providers.dart';
import 'package:gst_expense_scanner/shared/widgets/app_scaffold.dart';
import 'package:gst_expense_scanner/shared/widgets/primary_button.dart';

final _appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});

enum _LogoutChoice { cancel, syncFirst, logout }

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _loggingOut = false;

  Future<void> _logout() async {
    final pending = ref.read(syncStatusProvider).pendingCount;
    final failed = ref.read(homeNeedsAttentionCountProvider);
    final unsynced = pending + failed;

    final choice = await showDialog<_LogoutChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: Text(
          unsynced == 0
              ? 'You will need an OTP to sign in again.'
              : '$unsynced ${unsynced == 1 ? 'invoice has' : 'invoices have'} '
                    'not reached the server yet. Logging out deletes '
                    '${unsynced == 1 ? 'it' : 'them'} from this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _LogoutChoice.cancel),
            child: const Text('Cancel'),
          ),
          if (pending > 0)
            TextButton(
              onPressed: () => Navigator.pop(context, _LogoutChoice.syncFirst),
              child: const Text('Sync now'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, _LogoutChoice.logout),
            style: unsynced == 0
                ? null
                : TextButton.styleFrom(foregroundColor: Brand.danger),
            child: Text(unsynced == 0 ? 'Log out' : 'Log out anyway'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (choice == _LogoutChoice.syncFirst) {
      await ref.read(syncStatusProvider.notifier).syncNow();
      return;
    }
    if (choice != _LogoutChoice.logout) return;

    setState(() => _loggingOut = true);
    await ref.read(syncStatusProvider.notifier).stopEngineAndDrain();
    await ref.read(authStateProvider.notifier).logout();
    if (mounted) context.go('/login');
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    final opened =
        uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open the link')));
    }
  }

  @override
  Widget build(BuildContext context) {
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
    final version = ref.watch(_appVersionProvider).valueOrNull;

    return AppScaffold(
      title: 'Profile',
      body: ListView(
        padding: const EdgeInsets.all(20),
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
                  _infoRow('Mobile', IndianMobile.format(employee.mobile)),
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
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy policy'),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => _open(EnvConfig.privacyUrl),
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Terms of service'),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => _open(EnvConfig.termsUrl),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Log out',
            icon: Icons.logout,
            loading: _loggingOut,
            onPressed: _logout,
          ),
          if (version != null) ...[
            const SizedBox(height: 16),
            Text(
              'Version $version',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
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
