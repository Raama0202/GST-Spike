import 'dart:async';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/local_database.dart';
import '../../../shared/models/invoice_entity.dart';
import '../../../shared/models/notification_entity.dart';
import '../../uploads/data/datasources/invoice_local_datasource.dart';
import '../../uploads/data/datasources/invoice_remote_datasource.dart';

enum SyncEngineState { idle, running, stopped }

/// How the queue reacts to a failed upload.
enum UploadErrorKind {
  /// Server hiccup (5xx, 429, unexpected): back off, give up after the cap.
  retryable,

  /// Connection dropped or timed out: back off, never give up.
  network,

  /// Session or company problem (401/403): pause the queue without spending
  /// attempts; it resumes once the user signs in again.
  paused,

  /// Server says the bill is a duplicate (409): wait for an explicit override.
  duplicate,

  /// Server rejected the data (400/413/422) or the image is gone: retrying
  /// the same request cannot succeed, so wait for the employee.
  needsAttention,
}

UploadErrorKind classifyUploadFailure(AppFailure failure) {
  return switch (failure) {
    NetworkFailure() => UploadErrorKind.network,
    AuthFailure() => UploadErrorKind.paused,
    ServerFailure(statusCode: 409) => UploadErrorKind.duplicate,
    ServerFailure(statusCode: 400 || 413 || 422) =>
      UploadErrorKind.needsAttention,
    ValidationFailure() || StorageFailure() => UploadErrorKind.needsAttention,
    _ => UploadErrorKind.retryable,
  };
}

/// `base * 2^(attempts-1)`, capped.
Duration uploadBackoff(int attempts) {
  final exponent = (attempts - 1).clamp(0, 16);
  final delay = AppConstants.syncBaseBackoff * (1 << exponent);
  return delay > AppConstants.syncMaxBackoff
      ? AppConstants.syncMaxBackoff
      : delay;
}

enum _ItemOutcome { uploaded, failed, skipped, paused }

/// Processes the offline upload queue with exponential backoff.
class SyncEngine {
  SyncEngine({
    required InvoiceLocalDataSource localDataSource,
    required InvoiceRemoteDataSource remoteDataSource,
    ConnectivityService? connectivityService,
    InvoiceImageStore? imageStore,
    Duration loopInterval = const Duration(seconds: 15),
  })  : _local = localDataSource,
        _remote = remoteDataSource,
        _connectivity = connectivityService ?? ConnectivityService(),
        _imageStore = imageStore,
        _loopInterval = loopInterval;

  final InvoiceLocalDataSource _local;
  final InvoiceRemoteDataSource _remote;
  final ConnectivityService _connectivity;
  final InvoiceImageStore? _imageStore;
  final Duration _loopInterval;

  static const Duration _statusPullInterval = Duration(seconds: 45);
  static const int _statusPageSize = 100;
  static const int _maxStatusPages = 50;

  SyncEngineState _state = SyncEngineState.idle;

  /// Bumped by [stop]; a loop or run started under an older generation exits.
  int _generation = 0;
  Future<void>? _inFlight;
  Completer<void>? _wake;
  DateTime? _lastStatusPull;
  int _revision = 0;
  String? _lastError;

  SyncEngineState get state => _state;

  /// Bumps whenever a local invoice changes (upload or admin decision), so
  /// list screens know to reload.
  int get revision => _revision;

  /// Most recent upload problem; cleared by a run without failures.
  String? get lastError => _lastError;

  /// For changes made outside the engine (delete, resubmit, retry).
  void markChanged() => _revision++;

  Future<void> start() async {
    if (_state == SyncEngineState.running) return;
    _state = SyncEngineState.running;
    final generation = ++_generation;
    await recoverQueue();
    unawaited(_runLoop(generation));
  }

  void stop() {
    _generation++;
    _state = SyncEngineState.stopped;
    _wake?.complete();
    _wake = null;
  }

  /// Stops and waits (bounded) for an upload in progress to finish, so its
  /// result is not written after the caller clears local data.
  Future<void> stopAndDrain({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    stop();
    final running = _inFlight;
    if (running == null) return;
    try {
      await running.timeout(timeout);
    } catch (_) {}
  }

  /// Wakes the loop so newly queued work is picked up immediately.
  void nudge() {
    _wake?.complete();
    _wake = null;
  }

  /// [force] ignores backoff windows and re-reads the full server history.
  Future<void> syncNow({bool force = false}) async {
    final running = _inFlight;
    if (running != null) await running;
    if (!force && running != null) return;
    await _runOnce(force: force);
  }

  Future<int> pendingCount() => _local.pendingQueueCount();

  Future<void> recoverQueue() async {
    await _local.recoverStuckUploading();

    final queueItems = await _local.listQueueItems();
    for (final item in queueItems) {
      final invoice = await _local.getById(item.localInvoiceId);
      if (invoice == null) await _local.removeQueueItem(item.localInvoiceId);
    }
  }

  Future<void> _runLoop(int generation) async {
    while (generation == _generation) {
      try {
        await _runOnce();
      } catch (_) {
        // A storage hiccup must not kill the loop; the next tick retries.
      }
      if (generation != _generation) break;
      final wake = _wake = Completer<void>();
      await Future.any([Future<void>.delayed(_loopInterval), wake.future]);
    }
    if (generation == _generation) _state = SyncEngineState.idle;
  }

  /// Loop ticks and manual syncs share one in-flight run.
  Future<void> _runOnce({bool force = false}) {
    return _inFlight ??= _processQueueOnce(force: force).whenComplete(() {
      _inFlight = null;
    });
  }

  Future<void> _processQueueOnce({required bool force}) async {
    final generation = _generation;
    if (!await _connectivity.hasConnection) return;

    final queueItems = await _local.listQueueItems();
    var uploaded = false;
    var failed = false;
    for (final item in queueItems) {
      if (generation != _generation) break;
      if (!force && !_isReadyForAttempt(item)) continue;

      final outcome = await _processQueueItem(item);
      if (outcome == _ItemOutcome.uploaded) uploaded = true;
      if (outcome == _ItemOutcome.failed) failed = true;
      if (outcome == _ItemOutcome.paused) {
        failed = true;
        break;
      }
    }
    if (!failed && generation == _generation) _lastError = null;

    final last = _lastStatusPull;
    if (force ||
        uploaded ||
        last == null ||
        DateTime.now().difference(last) >= _statusPullInterval) {
      await pullStatuses(full: force);
    }
  }

  bool _isReadyForAttempt(UploadQueueItem item) {
    final nextAttemptAt = item.nextAttemptAt;
    if (nextAttemptAt == null) return true;
    return !DateTime.now().isBefore(nextAttemptAt);
  }

  /// Applies `GET /invoices/mine` so admin decisions reach My Uploads even
  /// when the notification was missed, and imports invoices this device has
  /// never seen (history after a reinstall) as read-only entries. Reads only
  /// changes since the last pull unless [full]. Returns how many local
  /// invoices changed or were added.
  Future<int> pullStatuses({bool full = false}) async {
    _lastStatusPull = DateTime.now();
    final startedAt = DateTime.now().toUtc();
    final since = full ? null : await _local.lastStatusPullAt();
    // Overlap absorbs clock skew between device and server.
    final updatedSince = since?.subtract(const Duration(minutes: 2));

    final remoteItems = <Map<String, dynamic>>[];
    try {
      for (var page = 1; page <= _maxStatusPages; page++) {
        final result = await _remote.fetchMinePage(
          page: page,
          pageSize: _statusPageSize,
          updatedSince: updatedSince,
        );
        remoteItems.addAll(result.items);
        if (result.items.length < _statusPageSize ||
            page * _statusPageSize >= result.total) {
          break;
        }
      }
    } catch (_) {
      return 0;
    }

    final changes = await _mergeRemote(remoteItems, refreshLinks: full);
    await _local.setLastStatusPullAt(startedAt);
    if (changes > 0) _revision++;
    return changes;
  }

  Future<int> _mergeRemote(
    List<Map<String, dynamic>> remoteItems, {
    required bool refreshLinks,
  }) async {
    if (remoteItems.isEmpty) return 0;
    final locals = await _local.list();
    final byServerId = {
      for (final invoice in locals)
        if (invoice.serverId != null) invoice.serverId!: invoice,
    };
    final byKey = {
      for (final invoice in locals)
        invoice.idempotencyKey ?? invoice.localId: invoice,
    };
    final tenantId = _local.tenantId;

    var changes = 0;
    for (final item in remoteItems) {
      final serverId = item['id'] as String?;
      final key = item['localIdempotencyKey'] as String?;
      final status = approvalStatusFromApi(
        (item['approvalStatus'] ?? item['status']) as String?,
      );
      if (serverId == null || status == null) continue;

      final local = byServerId[serverId] ?? (key == null ? null : byKey[key]);
      if (local == null) {
        if (tenantId == 'global') continue;
        final imported = InvoiceEntity.fromServer(
          item,
          companyId: tenantId,
          employeeId: '',
        );
        await _local.save(imported);
        byServerId[serverId] = imported;
        changes++;
        continue;
      }

      final remarks = item['adminRemarks'] as String?;
      final changed = local.approvalStatus != status ||
          local.serverId != serverId ||
          local.syncStatus != SyncStatus.uploaded ||
          (remarks != null && local.adminRemarks != remarks);
      if (!changed) {
        if (refreshLinks && local.isServerOnly) {
          await _local.save(
            local.copyWith(
              imageUrl: item['imageUrl'] as String?,
              thumbnailUrl: item['thumbnailUrl'] as String?,
            ),
          );
        }
        continue;
      }
      await _local.save(
        local.copyWith(
          serverId: serverId,
          approvalStatus: status,
          adminRemarks: remarks,
          syncStatus: SyncStatus.uploaded,
          clearUploadError: true,
          imageUrl: item['imageUrl'] as String?,
          thumbnailUrl: item['thumbnailUrl'] as String?,
          editedData: local.isServerOnly
              ? InvoiceEntity.mergeServerFields(
                  InvoiceFieldData.fromJson(
                    (item['editedData'] as Map?)?.cast<String, dynamic>(),
                  ),
                  item,
                )
              : null,
        ),
      );
      await _local.removeQueueItem(local.localId);
      changes++;
    }
    return changes;
  }

  Future<_ItemOutcome> _processQueueItem(UploadQueueItem item) async {
    final invoice = await _local.getById(item.localInvoiceId);
    if (invoice == null) {
      await _local.removeQueueItem(item.localInvoiceId);
      return _ItemOutcome.skipped;
    }

    if (invoice.syncStatus == SyncStatus.uploaded) {
      await _local.removeQueueItem(item.localInvoiceId);
      return _ItemOutcome.skipped;
    }

    final imagePath =
        invoice.compressedImagePath ?? invoice.originalImagePath;
    if (imagePath == null || imagePath.isEmpty) {
      await _markFailed(
        invoice: invoice,
        queueItem: item,
        failure: const StorageFailure(
          'The bill photo is missing on this device. Delete this entry and '
          'scan the bill again.',
        ),
      );
      return _ItemOutcome.failed;
    }

    final key = invoice.idempotencyKey ?? invoice.localId;
    await _local.save(
      invoice.copyWith(syncStatus: SyncStatus.uploading, idempotencyKey: key),
    );

    try {
      final serverId = await _remote.uploadInvoice(
        invoice: invoice.copyWith(idempotencyKey: key),
        imagePath: imagePath,
      );

      // The server keeps the original; the compressed copy and thumbnail are
      // enough for viewing it here.
      final dropOriginal = invoice.originalImagePath != null &&
          invoice.compressedImagePath != null &&
          invoice.originalImagePath != invoice.compressedImagePath;
      await _local.save(
        invoice.copyWith(
          serverId: serverId,
          syncStatus: SyncStatus.uploaded,
          approvalStatus: ApprovalStatus.uploaded,
          uploadedAt: DateTime.now(),
          uploadAttempts: item.attempts + 1,
          idempotencyKey: key,
          clearUploadError: true,
          clearOriginalImage: dropOriginal,
        ),
      );
      await _local.removeQueueItem(item.localInvoiceId);
      if (dropOriginal) {
        await _imageStore?.deleteFile(invoice.originalImagePath);
      }
      _revision++;
      return _ItemOutcome.uploaded;
    } on AppException catch (error) {
      return _markFailed(
        invoice: invoice,
        queueItem: item,
        failure: error.failure,
      );
    } catch (error) {
      return _markFailed(
        invoice: invoice,
        queueItem: item,
        failure: UnexpectedFailure(error.toString()),
      );
    }
  }

  Future<_ItemOutcome> _markFailed({
    required InvoiceEntity invoice,
    required UploadQueueItem queueItem,
    required AppFailure failure,
  }) async {
    final kind = classifyUploadFailure(failure);
    final key = invoice.idempotencyKey ?? invoice.localId;
    final now = DateTime.now();

    if (kind == UploadErrorKind.paused) {
      _lastError = failure.message;
      await _local.save(
        invoice.copyWith(
          syncStatus: SyncStatus.pending,
          lastUploadError: failure.message,
          idempotencyKey: key,
        ),
      );
      await _local.saveQueueItem(
        queueItem.copyWith(
          lastError: failure.message,
          nextAttemptAt: now.add(AppConstants.syncBaseBackoff),
        ),
      );
      return _ItemOutcome.paused;
    }

    final attempts = queueItem.attempts + 1;
    final giveUp = kind == UploadErrorKind.duplicate ||
        kind == UploadErrorKind.needsAttention ||
        (kind == UploadErrorKind.retryable &&
            attempts >= AppConstants.syncMaxAttempts);

    if (giveUp) {
      final message = kind == UploadErrorKind.duplicate
          ? 'The server already has a bill with this number and GSTIN. If '
              'this is a different bill, choose "Submit anyway".'
          : failure.message;
      _lastError = message;
      await _local.save(
        invoice.copyWith(
          syncStatus: SyncStatus.failed,
          uploadAttempts: attempts,
          lastUploadError: message,
          uploadErrorCode: switch (kind) {
            UploadErrorKind.duplicate => InvoiceEntity.errorDuplicate,
            UploadErrorKind.needsAttention => InvoiceEntity.errorRejected,
            _ => null,
          },
          idempotencyKey: key,
        ),
      );
      // Out of the queue: only "Retry now" / "Submit anyway" re-queues it.
      await _local.removeQueueItem(queueItem.localInvoiceId);
      _revision++;
      return _ItemOutcome.failed;
    }

    _lastError = failure.message;
    await _local.save(
      invoice.copyWith(
        syncStatus: SyncStatus.pending,
        uploadAttempts: attempts,
        lastUploadError: failure.message,
        idempotencyKey: key,
      ),
    );
    await _local.saveQueueItem(
      queueItem.copyWith(
        attempts: attempts,
        lastError: failure.message,
        nextAttemptAt: now.add(uploadBackoff(attempts)),
      ),
    );
    return _ItemOutcome.failed;
  }
}
