import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gst_expense_scanner/core/di/providers.dart';
import 'package:gst_expense_scanner/core/services/notification_service.dart';
import 'package:gst_expense_scanner/shared/models/notification_entity.dart';

import '../data/notification_local_datasource.dart';
import '../data/notification_remote_datasource.dart';
import '../data/notification_repository.dart';

/// Status updates arrive by polling until push (FCM) is wired up.
const notificationPollInterval = Duration(seconds: 30);

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
    onNewUnread: (n) => NotificationService.instance.show(
      id: n.id.hashCode & 0x7fffffff,
      title: n.title,
      body: n.body,
    ),
  );
});

final notificationsListProvider = FutureProvider<List<AppNotification>>((
  ref,
) async {
  final timer = Timer(notificationPollInterval, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  final repo = ref.watch(notificationRepositoryProvider);
  return repo.fetchAndCache();
});

final unreadNotificationCountProvider = Provider<int>((ref) {
  ref.watch(notificationsListProvider);
  return ref.watch(notificationRepositoryProvider).unreadCount();
});
