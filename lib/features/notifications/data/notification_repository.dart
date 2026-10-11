import 'package:gst_expense_scanner/shared/models/notification_entity.dart';

import 'notification_local_datasource.dart';
import 'notification_remote_datasource.dart';

/// Coordinates remote fetch and local notification cache.
class NotificationRepository {
  NotificationRepository({
    required NotificationRemoteDataSource remote,
    required NotificationLocalDataSource local,
    Future<void> Function(AppNotification notification)? onNewUnread,
  }) : _remote = remote,
       _local = local,
       _onNewUnread = onNewUnread;

  static const int _maxAlertsPerFetch = 3;

  final NotificationRemoteDataSource _remote;
  final NotificationLocalDataSource _local;
  final Future<void> Function(AppNotification notification)? _onNewUnread;

  /// Alerts only for unread items not seen before; the first fetch for a
  /// tenant just seeds the baseline so a fresh login never replays history.
  Future<List<AppNotification>> fetchAndCache() async {
    try {
      final hadBaseline = _local.hasCache();
      final knownIds = _local.readAll().map((n) => n.id).toSet();
      final remote = await _remote.fetchNotifications();
      await _local.saveAll(remote);

      final onNewUnread = _onNewUnread;
      if (onNewUnread != null && hadBaseline) {
        final fresh = remote
            .where((n) => !n.read && !knownIds.contains(n.id))
            .take(_maxAlertsPerFetch);
        for (final notification in fresh) {
          try {
            await onNewUnread(notification);
          } catch (_) {}
        }
      }
      return remote;
    } catch (_) {
      return _local.readAll();
    }
  }

  List<AppNotification> readCached() => _local.readAll();

  Future<void> markRead(String id) async {
    await _local.markReadLocal(id);
    try {
      await _remote.markRead(id);
    } catch (_) {
      // Local mark is sufficient offline.
    }
  }

  int unreadCount() => _local.unreadCount();
}
