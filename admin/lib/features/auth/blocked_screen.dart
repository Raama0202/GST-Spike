import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants.dart';
import '../../core/glass.dart';
import '../../core/session.dart';
import '../../shared/widgets.dart';
import 'auth.dart';

/// Shown when the API refuses the company (expired subscription or
/// suspension). Renewal happens in the web console, not in the app.
class BlockedScreen extends ConsumerWidget {
  const BlockedScreen({super.key});

  Future<void> _openConsole(BuildContext context) async {
    final ok = await launchUrl(
      Uri.parse(AppConstants.consoleUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      showSnack(context, 'Open ${AppConstants.consoleUrl} in a browser.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final block = ref.watch(accountBlockProvider);
    final signedIn = ref.watch(authProvider).value != null;
    final expired = block != AccountBlock.companySuspended;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: GlassCard(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: IconBadge(
                        icon: expired
                            ? Icons.event_busy_rounded
                            : Icons.block_rounded,
                        color: expired ? Brand.warning : Brand.danger,
                        size: 72,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      expired ? 'Subscription expired' : 'Company suspended',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      expired
                          ? 'Your company\'s subscription has ended, so '
                                'employees can\'t upload and admin tools are '
                                'paused. Renew it in the web console, then '
                                'tap Try again.'
                          : 'This company account has been suspended. '
                                'Contact support to restore access.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (expired) ...[
                      GlassButton(
                        label: 'Renew in web console',
                        icon: Icons.open_in_new_rounded,
                        onPressed: () => _openConsole(context),
                      ),
                      const SizedBox(height: 12),
                    ],
                    OutlinedButton.icon(
                      onPressed: () =>
                          ref.read(accountBlockProvider.notifier).clear(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => signedIn
                          ? ref.read(authProvider.notifier).logout()
                          : ref.read(accountBlockProvider.notifier).clear(),
                      child: Text(signedIn ? 'Sign out' : 'Back to sign in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
