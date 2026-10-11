import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets.dart';
import 'auth.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authProvider).value;
    return ContentPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(
            title: 'Profile',
            subtitle: 'Your current administrator session.',
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 30,
                    child: Text(
                      (session?.name ?? session?.email ?? 'A')[0].toUpperCase(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    session?.name ?? 'Administrator',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (session?.email != null) Text(session!.email!),
                  const SizedBox(height: 6),
                  const StatusPill('Company Admin'),
                  if (session?.companyId != null) ...[
                    const SizedBox(height: 16),
                    SelectableText('Company ID: ${session!.companyId}'),
                  ],
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: () => ref.read(authProvider.notifier).logout(),
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
