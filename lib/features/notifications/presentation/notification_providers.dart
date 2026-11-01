import 'dart:async';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gst_expense_scanner/core/di/providers.dart';
import 'package:gst_expense_scanner/core/services/notification_service.dart';
import 'package:gst_expense_scanner/core/services/push_service.dart';
import 'package:gst_expense_scanner/features/auth/presentation/providers/auth_providers.dart';
import 'package:gst_expense_scanner/shared/models/notification_entity.dart';

import '../data/notification_local_datasource.dart';
import '../data/notification_remote_datasource.dart';
import '../data/notification_repository.dart';

/// Inbox refresh interval while the app is in the foreground.
const notificationPollInterval = Duration(seconds: 60);

final notificationLocalDataSourceProvider =
    Provider<NotificationLocalDataSource>((ref) {
      return NotificationLocalDataSource(ref.watch(localDatabaseProvider));
    });

final notificationRemoteDataSourceProvider =
    Provider<NotificationRemoteDataSource>((ref) {
      return NotificationRemoteDataSource(ref.watch(apiClientProvider));
    });

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(
    remote: ref.watch(notificationRemoteDataSourceProvider),
    local: ref.watch(notificationLocalDataSourceProvider),
    onNewUnread: (n) async {
      if (PushService.instance.active) return;
      await NotificationService.instance.show(
        id: n.id.hashCode & 0x7fffffff,
        title: n.title,
        body: n.body,
        payload: n.invoiceServerId,
      );
    },
  );
});

/// Polls only while signed in and in the foreground; returning to the app
/// rebuilds this provider, which fetches immediately.
final notificationsListProvider = FutureProvider<List<AppNotification>>((
  ref,
) async {
  final signedIn = ref.watch(
    authStateProvider.select((s) => s is AuthAuthenticated),
  );
  if (!signedIn) return const [];
  final repo = ref.watch(notificationRepositoryProvider);
  if (ref.watch(appLifecycleProvider) != AppLifecycleState.resumed) {
    try {
      return repo.readCached();
    } catch (_) {
      return const [];
    }
  }
  final timer = Timer(notificationPollInterval, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return repo.fetchAndCache();
});

final unreadNotificationCountProvider = Provider<int>((ref) {
  final items = ref.watch(notificationsListProvider).valueOrNull ?? const [];
  return items.where((n) => !n.read).length;
});
