import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gst_expense_scanner/core/theme/glass.dart';
import 'package:gst_expense_scanner/features/home/presentation/providers/home_providers.dart';
import 'package:gst_expense_scanner/features/notifications/presentation/notification_providers.dart';
import 'package:gst_expense_scanner/features/sync/presentation/sync_providers.dart';
import 'package:gst_expense_scanner/shared/widgets/primary_button.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brand = theme.colorScheme.primary;
    final companyName = ref.watch(homeCompanyNameProvider);
    final employeeName = ref.watch(homeEmployeeNameProvider);
    final todayCount = ref.watch(homeTodayUploadCountProvider);
    final pendingSync = ref.watch(homePendingSyncCountProvider);
    final syncStatus = ref.watch(syncStatusProvider);
    final unread = ref.watch(unreadNotificationCountProvider);
    final syncing = syncStatus.state == SyncStatusView.syncing;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            GlassMetrics.screenPadding,
            12,
            GlassMetrics.screenPadding,
            28,
          ),
          children: [
            Row(
              children: [
                IconBadge(
                  icon: Icons.apartment_rounded,
                  color: brand,
                  size: 44,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    companyName.isEmpty ? 'Home' : companyName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                GlassIconButton(
                  icon: Icons.notifications_none_rounded,
                  tooltip: 'Notifications',
                  badge: unread,
                  onPressed: () => context.push('/notifications'),
                ),
                const SizedBox(width: 10),
                GlassIconButton(
                  icon: Icons.person_outline_rounded,
                  tooltip: 'Profile',
                  onPressed: () => context.push('/profile'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Hello, $employeeName', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 6),
            Text(
              'Capture GST invoices quickly and sync when online.',
              style: theme.textTheme.bodyLarge?.copyWith(color: Brand.muted),
            ),
            const SizedBox(height: 22),
            _ScanHero(onTap: () => context.push('/scan-processing')),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: "Today's uploads",
                    value: todayCount.when(
                      data: (v) => '$v',
                      loading: () => '…',
                      error: (_, __) => '—',
                    ),
                    icon: Icons.upload_file_rounded,
                    color: brand,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatTile(
                    label: 'Pending sync',
                    value: '$pendingSync',
                    icon: Icons.sync_rounded,
                    color: pendingSync > 0 ? Brand.warning : Brand.success,
                  ),
                ),
              ],
            ),
            if (syncing) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: const LinearProgressIndicator(minHeight: 6),
              ),
              const SizedBox(height: 6),
              Text('Syncing uploads…', style: theme.textTheme.bodyMedium),
            ],
            if (syncStatus.lastError != null) ...[
              const SizedBox(height: 14),
              GlassCard(
                tint: Brand.danger,
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Brand.danger,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        syncStatus.lastError!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Brand.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 26),
            const GlassSectionHeader(title: 'Quick actions'),
            const SizedBox(height: 12),
            _ActionTile(
              icon: Icons.folder_open_rounded,
              color: Brand.violet,
              title: 'My Uploads',
              subtitle: 'Track approvals and sync status',
              onTap: () => context.push('/uploads'),
            ),
            const SizedBox(height: 10),
            _ActionTile(
              icon: Icons.notifications_active_rounded,
              color: Brand.pink,
              title: 'Notifications',
              subtitle: unread > 0 ? '$unread unread' : 'You are all caught up',
              onTap: () => context.push('/notifications'),
            ),
            const SizedBox(height: 10),
            _ActionTile(
              icon: Icons.badge_rounded,
              color: Brand.cyan,
              title: 'Profile',
              subtitle: 'Account, device and sign out',
              onTap: () => context.push('/profile'),
            ),
            const SizedBox(height: 22),
            PrimaryButton(
              label: syncing ? 'Syncing…' : 'Sync Now',
              icon: Icons.cloud_upload_rounded,
              loading: syncing,
              onPressed: syncing
                  ? null
                  : () => ref.read(syncStatusProvider.notifier).syncNow(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanHero extends StatelessWidget {
  const _ScanHero({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.colorScheme.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GlassMetrics.radius + 4),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [brand, Brand.violet, Brand.pink.withValues(alpha: 0.9)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: brand.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(GlassMetrics.radius + 4),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scan Invoice',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Auto-crop, read GST details and upload in seconds.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Start scanning',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.2),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.55),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.document_scanner_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, color: color, size: 38),
          const SizedBox(height: 12),
          Text(value, style: theme.textTheme.headlineMedium),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: Brand.muted),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          IconBadge(icon: icon, color: color, size: 42),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Brand.muted),
        ],
      ),
    );
  }
}
