import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/storage/local_database.dart';
import '../../../../shared/models/invoice_entity.dart';
import '../../domain/repositories/invoice_repository.dart';
import '../datasources/invoice_local_datasource.dart';
import '../datasources/invoice_remote_datasource.dart';

/// Coordinates local Hive storage and remote invoice APIs.
class InvoiceRepositoryImpl implements InvoiceRepository {
  InvoiceRepositoryImpl({
    required InvoiceLocalDataSource localDataSource,
    required InvoiceRemoteDataSource remoteDataSource,
    InvoiceImageStore? imageStore,
    Duration duplicateCheckTimeout = AppConstants.duplicateCheckTimeout,
    Uuid? uuid,
  })  : _local = localDataSource,
        _remote = remoteDataSource,
        _imageStore = imageStore ?? InvoiceImageStore(),
        _duplicateCheckTimeout = duplicateCheckTimeout,
        _uuid = uuid ?? const Uuid();

  final InvoiceLocalDataSource _local;
  final InvoiceRemoteDataSource _remote;
  final InvoiceImageStore _imageStore;
  final Duration _duplicateCheckTimeout;
  final Uuid _uuid;

  @override
  Future<InvoiceEntity> createFromScan({
    required String companyId,
    required String employeeId,
    required String branchId,
    required String deviceId,
    required InvoiceFieldData ocrData,
    required InvoiceFieldData editedData,
    required double ocrConfidence,
    required String originalImagePath,
    required String compressedImagePath,
    required String thumbnailPath,
    String? localId,
    double? latitude,
    double? longitude,
    bool duplicateOverride = false,
  }) async {
    final id = localId ?? _uuid.v4();
    final invoice = InvoiceEntity(
      localId: id,
      companyId: companyId,
      employeeId: employeeId,
      branchId: branchId,
      deviceId: deviceId,
      createdAt: DateTime.now(),
      syncStatus: SyncStatus.pending,
      approvalStatus: ApprovalStatus.pending,
      ocrData: ocrData,
      editedData: editedData,
      ocrConfidence: ocrConfidence,
      originalImagePath: originalImagePath,
      compressedImagePath: compressedImagePath,
      thumbnailPath: thumbnailPath,
      latitude: latitude,
      longitude: longitude,
      idempotencyKey: id,
      duplicateOverride: duplicateOverride,
    );

    await _local.save(invoice);
    return invoice;
  }

  @override
  Future<InvoiceEntity> updateEdited({
    required String localId,
    required InvoiceFieldData editedData,
    bool duplicateOverride = false,
  }) async {
    final existing = await _local.getById(localId);
    if (existing == null) {
      throw StateError('Invoice $localId not found.');
    }

    final updated = existing.copyWith(
      editedData: editedData,
      duplicateOverride: duplicateOverride,
    );
    await _local.save(updated);
    return updated;
  }

  @override
  Future<void> enqueue(String localId) async {
    final invoice = await _local.getById(localId);
    if (invoice == null) {
      throw StateError('Invoice $localId not found.');
    }

    if (invoice.syncStatus == SyncStatus.uploaded) return;

    await _local.save(
      invoice.copyWith(
        syncStatus: SyncStatus.pending,
        idempotencyKey: invoice.idempotencyKey ?? invoice.localId,
      ),
    );
    await _local.enqueue(localId);
  }

  @override
  Future<List<InvoiceEntity>> list({SyncStatus? syncStatus}) {
    return _local.list(syncStatus: syncStatus);
  }

  @override
  Future<InvoiceEntity?> getById(String localId) {
    return _local.getById(localId);
  }

  @override
  Future<InvoiceEntity?> getByServerId(String serverId) {
    return _local.getByServerId(serverId);
  }

  @override
  Future<DuplicateCheckResult> checkDuplicate(
    InvoiceFieldData data, {
    String? excludeLocalId,
  }) async {
    final localMatches = await _local.findLocalDuplicates(
      gstin: data.gstin,
      invoiceNumber: data.invoiceNumber,
      invoiceDate: data.invoiceDate,
      excludeLocalId: excludeLocalId,
    );

    if (localMatches.isNotEmpty) {
      final match = localMatches.first;
      return DuplicateCheckResult(
        isDuplicate: true,
        existingLocalId: match.localId,
        existingServerId: match.serverId,
        source: 'local',
        message: 'This invoice already exists on this device.',
      );
    }

    if (data.gstin == null || data.invoiceNumber == null) {
      return const DuplicateCheckResult(isDuplicate: false);
    }

    // Any failure here (offline, timeout, server down, expired session) must
    // not stop the invoice being saved: the upload endpoint re-checks.
    try {
      return await _remote
          .checkDuplicate(data, timeout: _duplicateCheckTimeout)
          .timeout(_duplicateCheckTimeout);
    } on TimeoutException {
      return const DuplicateCheckResult.unknown();
    } on AppException {
      return const DuplicateCheckResult.unknown();
    } catch (_) {
      return const DuplicateCheckResult.unknown();
    }
  }

  @override
  Future<void> deleteLocal(String localId) async {
    final invoice = await _local.getById(localId);
    if (invoice == null) return;
    if (!invoice.canDeleteLocally) {
      throw StateError('Uploaded invoices cannot be deleted from the device.');
    }
    await _local.delete(localId);
    await _imageStore.deleteForPaths([
      invoice.originalImagePath,
      invoice.compressedImagePath,
      invoice.thumbnailPath,
    ]);
  }

  @override
  Future<void> retryNow(String localId, {bool duplicateOverride = false}) async {
    final invoice = await _local.getById(localId);
    if (invoice == null || invoice.syncStatus == SyncStatus.uploaded) return;
    await _local.removeQueueItem(localId);
    await _local.save(
      invoice.copyWith(
        syncStatus: SyncStatus.pending,
        uploadAttempts: 0,
        duplicateOverride: duplicateOverride || invoice.duplicateOverride,
        idempotencyKey: invoice.idempotencyKey ?? invoice.localId,
        clearUploadError: true,
      ),
    );
    await _local.enqueue(localId);
  }

  @override
  Future<ServerInvoiceDetail> fetchServerInvoice(String serverId) async {
    final json = await _remote.fetchInvoice(serverId);
    final history = [
      for (final entry in (json['history'] as List?) ?? const [])
        if (entry is Map)
          InvoiceHistoryEntry.fromJson(Map<String, dynamic>.from(entry)),
    ];

    final existing = await _local.getByServerId(serverId);
    final status = approvalStatusFromApi(json['approvalStatus'] as String?);
    final InvoiceEntity invoice;
    if (existing == null) {
      invoice = InvoiceEntity.fromServer(
        json,
        companyId: _local.tenantId,
        employeeId: '',
      );
      await _local.save(invoice);
    } else {
      invoice = existing.copyWith(
        approvalStatus: status,
        adminRemarks: json['adminRemarks'] as String?,
        imageUrl: json['imageUrl'] as String?,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        editedData: existing.isServerOnly
            ? InvoiceEntity.mergeServerFields(
                InvoiceFieldData.fromJson(
                  (json['editedData'] as Map?)?.cast<String, dynamic>(),
                ),
                json,
              )
            : null,
      );
      await _local.save(invoice);
    }
    return ServerInvoiceDetail(invoice: invoice, history: history);
  }

  @override
  Future<InvoiceEntity> resubmit({
    required InvoiceEntity invoice,
    required InvoiceFieldData editedData,
    String? note,
  }) async {
    final serverId = invoice.serverId;
    if (serverId == null) {
      throw StateError('Only uploaded invoices can be resubmitted.');
    }
    final json = await _remote.resubmit(
      serverId: serverId,
      editedData: editedData,
      categoryId: editedData.expenseCategoryId,
      note: note,
    );
    final updated = invoice.copyWith(
      editedData: editedData,
      approvalStatus: approvalStatusFromApi(json['approvalStatus'] as String?) ??
          ApprovalStatus.uploaded,
      syncStatus: SyncStatus.uploaded,
    );
    await _local.save(updated);
    return updated;
  }
}
