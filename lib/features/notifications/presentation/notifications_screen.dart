import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:gst_expense_scanner/core/theme/glass.dart';
import 'package:gst_expense_scanner/features/notifications/presentation/notification_providers.dart';
import 'package:gst_expense_scanner/shared/widgets/app_scaffold.dart';
import 'package:gst_expense_scanner/shared/widgets/error_view.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsListProvider);
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Notifications',
      body: notifications.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(
          message: error.toString(),
          onRetry: () => ref.invalidate(notificationsListProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => ref.refresh(notificationsListProvider.future),
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: constraints.maxHeight,
                    child: Center(
                      child: Text(
                        'No notifications yet.',
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.refresh(notificationsListProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final notification = items[index];
                return Card(
                  color: notification.read
                      ? null
                      : Color.alphaBlend(
                          theme.colorScheme.primary.withValues(alpha: 0.08),
                          Colors.white.withValues(alpha: 0.75),
                        ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: IconBadge(
                      icon: notification.read
                          ? Icons.notifications_none_rounded
                          : Icons.notifications_active_rounded,
                      color: notification.read ? Brand.muted : Brand.pink,
                    ),
                    title: Text(
                      notification.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: notification.read
                            ? FontWeight.w500
                            : FontWeight.w700,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 6),
                        Text(notification.body),
                        const SizedBox(height: 6),
                        Text(
                          DateFormat(
                            'dd MMM yyyy, hh:mm a',
                          ).format(notification.createdAt),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                    onTap: () async {
                      await ref
                          .read(notificationRepositoryProvider)
                          .markRead(notification.id);
                      ref.invalidate(notificationsListProvider);

                      if (notification.invoiceLocalId != null &&
                          context.mounted) {
                        context.push('/uploads/${notification.invoiceLocalId}');
                      }
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
