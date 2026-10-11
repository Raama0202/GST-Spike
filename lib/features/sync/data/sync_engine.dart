import 'dart:async';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/invoice_entity.dart';
import '../../../shared/models/notification_entity.dart';
import '../../uploads/data/datasources/invoice_local_datasource.dart';
import '../../uploads/data/datasources/invoice_remote_datasource.dart';

enum SyncEngineState { idle, running, stopped }

/// Processes the offline upload queue with exponential backoff.
class SyncEngine {
  SyncEngine({
    required InvoiceLocalDataSource localDataSource,
    required InvoiceRemoteDataSource remoteDataSource,
    ConnectivityService? connectivityService,
  })  : _local = localDataSource,
        _remote = remoteDataSource,
        _connectivity = connectivityService ?? ConnectivityService();

  final InvoiceLocalDataSource _local;
  final InvoiceRemoteDataSource _remote;
  final ConnectivityService _connectivity;

  static const Duration _statusPullInterval = Duration(seconds: 45);

  SyncEngineState _state = SyncEngineState.idle;
  bool _stopRequested = false;
  Completer<void>? _activeRun;
  DateTime? _lastStatusPull;
  int _revision = 0;

  SyncEngineState get state => _state;

  /// Bumps whenever a local invoice changes (upload or admin decision), so
  /// list screens know to reload.
  int get revision => _revision;

  Future<void> start() async {
    if (_state == SyncEngineState.running) return;
    _stopRequested = false;
    _state = SyncEngineState.running;
    await recoverQueue();
    unawaited(_runLoop());
  }

  void stop() {
    _stopRequested = true;
    _state = SyncEngineState.stopped;
  }

  Future<void> syncNow() async {
    if (_activeRun != null && !_activeRun!.isCompleted) {
      await _activeRun!.future;
      return;
    }
    await _processQueueOnce();
  }

  Future<int> pendingCount() => _local.pendingQueueCount();

  Future<void> recoverQueue() async {
    await _local.recoverStuckUploading();

    final queueItems = await _local.listQueueItems();
    for (final item in queueItems) {
      final invoice = await _local.getById(item.localInvoiceId);
      if (invoice == null) {
        await _local.removeQueueItem(item.localInvoiceId);
        continue;
      }

      if (invoice.syncStatus == SyncStatus.uploading) {
        await _local.save(
          invoice.copyWith(
            syncStatus: SyncStatus.pending,
            lastUploadError: null,
          ),
        );
      }
    }
  }

  Future<void> _runLoop() async {
    while (!_stopRequested) {
      await _processQueueOnce();
      await Future<void>.delayed(const Duration(seconds: 15));
    }
    _state = SyncEngineState.idle;
  }

  Future<void> _processQueueOnce() async {
    _activeRun = Completer<void>();
    try {
      if (!await _connectivity.hasConnection) return;

      final queueItems = await _local.listQueueItems();
      var uploaded = false;
      for (final item in queueItems) {
        if (_stopRequested) break;

        if (!_isReadyForAttempt(item)) continue;

        uploaded = await _processQueueItem(item) || uploaded;
      }

      final last = _lastStatusPull;
      if (uploaded ||
          last == null ||
          DateTime.now().difference(last) >= _statusPullInterval) {
        await pullStatuses();
      }
    } finally {
      if (!_activeRun!.isCompleted) {
        _activeRun!.complete();
      }
    }
  }

  bool _isReadyForAttempt(UploadQueueItem item) {
    final nextAttemptAt = item.nextAttemptAt;
    if (nextAttemptAt == null) return true;
    return !DateTime.now().isBefore(nextAttemptAt);
  }

  /// Applies `GET /invoices/mine` so admin decisions reach My Uploads even
  /// when the notification was missed. Returns how many invoices changed.
  Future<int> pullStatuses() async {
    _lastStatusPull = DateTime.now();
    final List<Map<String, dynamic>> remoteItems;
    try {
      remoteItems = await _remote.fetchMine();
    } catch (_) {
      return 0;
    }
    if (remoteItems.isEmpty) return 0;

    final locals = await _local.list();
    var changes = 0;
    for (final item in remoteItems) {
      final serverId = item['id'] as String?;
      final key = item['localIdempotencyKey'] as String?;
      final status = _approvalFromApi(
        (item['approvalStatus'] ?? item['status']) as String?,
      );
      if (serverId == null || status == null) continue;

      final local = locals.where((invoice) {
        return invoice.serverId == serverId ||
            (key != null && (invoice.idempotencyKey ?? invoice.localId) == key);
      }).firstOrNull;
      if (local == null) continue;

      final remarks = item['adminRemarks'] as String?;
      if (local.approvalStatus == status &&
          local.serverId == serverId &&
          local.syncStatus == SyncStatus.uploaded &&
          (remarks == null || local.adminRemarks == remarks)) {
        continue;
      }
      await _local.save(
        local.copyWith(
          serverId: serverId,
          approvalStatus: status,
          adminRemarks: remarks,
          syncStatus: SyncStatus.uploaded,
        ),
      );
      await _local.removeQueueItem(local.localId);
      changes++;
    }
    if (changes > 0) _revision++;
    return changes;
  }

  ApprovalStatus? _approvalFromApi(String? value) {
    switch (value?.toLowerCase()) {
      case 'pending':
      case 'uploaded':
        return ApprovalStatus.uploaded;
      case 'approved':
        return ApprovalStatus.approved;
      case 'rejected':
        return ApprovalStatus.rejected;
      case 'returned':
        return ApprovalStatus.returned;
      default:
        return null;
    }
  }

  /// Returns true when the invoice reached the server.
  Future<bool> _processQueueItem(UploadQueueItem item) async {
    final invoice = await _local.getById(item.localInvoiceId);
    if (invoice == null) {
      await _local.removeQueueItem(item.localInvoiceId);
      return false;
    }

    if (invoice.syncStatus == SyncStatus.uploaded) {
      await _local.removeQueueItem(item.localInvoiceId);
      return false;
    }

    final imagePath =
        invoice.compressedImagePath ?? invoice.originalImagePath;
    if (imagePath == null || imagePath.isEmpty) {
      await _markFailed(
        invoice: invoice,
        queueItem: item,
        error: 'Missing invoice image for upload.',
        retryable: false,
      );
      return false;
    }

    await _local.save(
      invoice.copyWith(
        syncStatus: SyncStatus.uploading,
        idempotencyKey: invoice.idempotencyKey ?? invoice.localId,
      ),
    );

    try {
      final serverId = await _remote.uploadInvoice(
        invoice: invoice.copyWith(
          idempotencyKey: invoice.idempotencyKey ?? invoice.localId,
        ),
        imagePath: imagePath,
      );

      await _local.save(
        invoice.copyWith(
          serverId: serverId,
          syncStatus: SyncStatus.uploaded,
          approvalStatus: ApprovalStatus.uploaded,
          uploadedAt: DateTime.now(),
          uploadAttempts: item.attempts + 1,
          lastUploadError: null,
          idempotencyKey: invoice.idempotencyKey ?? invoice.localId,
        ),
      );
      await _local.removeQueueItem(item.localInvoiceId);
      _revision++;
      return true;
    } on AppException catch (error) {
      await _markFailed(
        invoice: invoice,
        queueItem: item,
        error: error.failure.message,
        retryable: true,
      );
    } catch (error) {
      await _markFailed(
        invoice: invoice,
        queueItem: item,
        error: error.toString(),
        retryable: true,
      );
    }
    return false;
  }

  Future<void> _markFailed({
    required InvoiceEntity invoice,
    required UploadQueueItem queueItem,
    required String error,
    required bool retryable,
  }) async {
    final attempts = queueItem.attempts + 1;
    final maxAttempts = AppConstants.syncMaxAttempts;

    if (!retryable || attempts >= maxAttempts) {
      await _local.save(
        invoice.copyWith(
          syncStatus: SyncStatus.failed,
          uploadAttempts: attempts,
          lastUploadError: error,
          idempotencyKey: invoice.idempotencyKey ?? invoice.localId,
        ),
      );
      await _local.saveQueueItem(
        queueItem.copyWith(
          attempts: attempts,
          lastError: error,
          nextAttemptAt: null,
        ),
      );
      return;
    }

    final backoff = _computeBackoff(attempts);
    await _local.save(
      invoice.copyWith(
        syncStatus: SyncStatus.pending,
        uploadAttempts: attempts,
        lastUploadError: error,
        idempotencyKey: invoice.idempotencyKey ?? invoice.localId,
      ),
    );
    await _local.saveQueueItem(
      queueItem.copyWith(
        attempts: attempts,
        lastError: error,
        nextAttemptAt: DateTime.now().add(backoff),
      ),
    );
  }

  Duration _computeBackoff(int attempts) {
    final multiplier = 1 << (attempts - 1).clamp(0, 10);
    return AppConstants.syncBaseBackoff * multiplier;
  }
}
