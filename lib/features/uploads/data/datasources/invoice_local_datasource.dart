import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/storage/local_database.dart';
import '../../../../shared/models/invoice_entity.dart';
import '../../../../shared/models/notification_entity.dart';

/// Hive-backed invoice persistence.
class InvoiceLocalDataSource {
  InvoiceLocalDataSource(this._database);

  final LocalDatabase _database;

  Future<void> save(InvoiceEntity invoice) async {
    try {
      await _database.invoices.put(invoice.localId, invoice.toJson());
    } catch (error) {
      throw AppException(
        CacheFailure('Failed to save invoice locally: $error'),
      );
    }
  }

  Future<InvoiceEntity?> getById(String localId) async {
    try {
      final raw = _database.invoices.get(localId);
      if (raw == null) return null;
      return InvoiceEntity.fromJson(Map<String, dynamic>.from(raw as Map));
    } catch (error) {
      throw AppException(
        CacheFailure('Failed to read invoice $localId: $error'),
      );
    }
  }

  Future<List<InvoiceEntity>> list({SyncStatus? syncStatus}) async {
    try {
      final items = _database.invoices.values
          .map((raw) => InvoiceEntity.fromJson(
                Map<String, dynamic>.from(raw as Map),
              ))
          .toList();

      if (syncStatus != null) {
        return items.where((item) => item.syncStatus == syncStatus).toList();
      }

      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    } catch (error) {
      throw AppException(
        CacheFailure('Failed to list invoices: $error'),
      );
    }
  }

  Future<List<InvoiceEntity>> findLocalDuplicates({
    required String? gstin,
    required String? invoiceNumber,
    required DateTime? invoiceDate,
    String? excludeLocalId,
  }) async {
    final all = await list();
    return all.where((invoice) {
      if (excludeLocalId != null && invoice.localId == excludeLocalId) {
        return false;
      }
      if (invoice.syncStatus == SyncStatus.failed &&
          invoice.duplicateOverride) {
        return false;
      }

      final data = invoice.displayData;
      final gstinMatch = gstin != null &&
          data.gstin != null &&
          data.gstin!.toUpperCase() == gstin.toUpperCase();
      final numberMatch = invoiceNumber != null &&
          data.invoiceNumber != null &&
          data.invoiceNumber!.trim().toUpperCase() ==
              invoiceNumber.trim().toUpperCase();
      final dateMatch = invoiceDate != null &&
          data.invoiceDate != null &&
          _sameDay(data.invoiceDate!, invoiceDate);

      return gstinMatch && numberMatch && (dateMatch || invoiceDate == null);
    }).toList();
  }

  Future<void> enqueue(String localInvoiceId) async {
    try {
      final existing = _database.uploadQueue.get(localInvoiceId);
      if (existing != null) return;

      final item = UploadQueueItem(
        localInvoiceId: localInvoiceId,
        enqueuedAt: DateTime.now(),
        attempts: 0,
      );
      await _database.uploadQueue.put(localInvoiceId, item.toJson());
    } catch (error) {
      throw AppException(
        CacheFailure('Failed to enqueue invoice $localInvoiceId: $error'),
      );
    }
  }

  Future<List<UploadQueueItem>> listQueueItems() async {
    try {
      return _database.uploadQueue.values
          .map(
            (raw) => UploadQueueItem.fromJson(
              Map<String, dynamic>.from(raw as Map),
            ),
          )
          .toList()
        ..sort((a, b) => a.enqueuedAt.compareTo(b.enqueuedAt));
    } catch (error) {
      throw AppException(
        CacheFailure('Failed to read upload queue: $error'),
      );
    }
  }

  Future<UploadQueueItem?> getQueueItem(String localInvoiceId) async {
    try {
      final raw = _database.uploadQueue.get(localInvoiceId);
      if (raw == null) return null;
      return UploadQueueItem.fromJson(Map<String, dynamic>.from(raw as Map));
    } catch (error) {
      throw AppException(
        CacheFailure('Failed to read queue item $localInvoiceId: $error'),
      );
    }
  }

  Future<void> saveQueueItem(UploadQueueItem item) async {
    try {
      await _database.uploadQueue.put(item.localInvoiceId, item.toJson());
    } catch (error) {
      throw AppException(
        CacheFailure('Failed to save queue item: $error'),
      );
    }
  }

  Future<void> removeQueueItem(String localInvoiceId) async {
    try {
      await _database.uploadQueue.delete(localInvoiceId);
    } catch (error) {
      throw AppException(
        CacheFailure('Failed to remove queue item: $error'),
      );
    }
  }

  Future<int> pendingQueueCount() async {
    final items = await listQueueItems();
    return items.length;
  }

  Future<void> recoverStuckUploading() async {
    final uploading = await list(syncStatus: SyncStatus.uploading);
    for (final invoice in uploading) {
      await save(
        invoice.copyWith(
          syncStatus: SyncStatus.pending,
          lastUploadError: null,
        ),
      );
    }
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
