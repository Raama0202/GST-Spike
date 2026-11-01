import 'package:gst_expense_scanner/core/errors/exceptions.dart';
import 'package:gst_expense_scanner/core/errors/failures.dart';
import 'package:gst_expense_scanner/core/storage/local_database.dart';
import 'package:gst_expense_scanner/shared/models/notification_entity.dart';

/// Hive-backed notification cache.
class NotificationLocalDataSource {
  NotificationLocalDataSource(this._database);

  static const String _listKey = 'items';
  static const String _pendingReadKey = 'pendingRead';

  final LocalDatabase _database;

  Future<void> saveAll(List<AppNotification> notifications) async {
    try {
      final payload = notifications.map((n) => n.toJson()).toList();
      await _database.notifications.put(_listKey, payload);
    } catch (error) {
      throw AppException(CacheFailure('Failed to cache notifications: $error'));
    }
  }

  /// False until the first successful fetch for this tenant has been cached.
  bool hasCache() => _database.notifications.containsKey(_listKey);

  List<AppNotification> readAll() {
    try {
      final raw = _database.notifications.get(_listKey);
      if (raw is! List) return const [];
      return raw
          .map(
            (item) => AppNotification.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (error) {
      throw AppException(CacheFailure('Failed to read notifications: $error'));
    }
  }

  Future<void> markReadLocal(String id) async {
    final items = readAll();
    final updated = items
        .map((n) => n.id == id ? n.copyWith(read: true) : n)
        .toList();
    await saveAll(updated);
  }

  /// Ids marked read while the server could not be told.
  Set<String> pendingReadIds() {
    final raw = _database.notifications.get(_pendingReadKey);
    return raw is List ? raw.whereType<String>().toSet() : <String>{};
  }

  Future<void> addPendingRead(String id) async {
    await _database.notifications.put(
      _pendingReadKey,
      {...pendingReadIds(), id}.toList(),
    );
  }

  Future<void> removePendingRead(Iterable<String> ids) async {
    final remaining = pendingReadIds()..removeAll(ids);
    if (remaining.isEmpty) {
      await _database.notifications.delete(_pendingReadKey);
    } else {
      await _database.notifications.put(_pendingReadKey, remaining.toList());
    }
  }

  int unreadCount() => readAll().where((n) => !n.read).length;
}
