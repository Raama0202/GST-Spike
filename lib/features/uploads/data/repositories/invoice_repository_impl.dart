import 'package:uuid/uuid.dart';

import '../../../../shared/models/invoice_entity.dart';
import '../../domain/repositories/invoice_repository.dart';
import '../datasources/invoice_local_datasource.dart';
import '../datasources/invoice_remote_datasource.dart';

/// Coordinates local Hive storage and remote invoice APIs.
class InvoiceRepositoryImpl implements InvoiceRepository {
  InvoiceRepositoryImpl({
    required InvoiceLocalDataSource localDataSource,
    required InvoiceRemoteDataSource remoteDataSource,
    Uuid? uuid,
  })  : _local = localDataSource,
        _remote = remoteDataSource,
        _uuid = uuid ?? const Uuid();

  final InvoiceLocalDataSource _local;
  final InvoiceRemoteDataSource _remote;
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
    double? latitude,
    double? longitude,
  }) async {
    final localId = _uuid.v4();
    final invoice = InvoiceEntity(
      localId: localId,
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
      idempotencyKey: localId,
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

    return _remote.checkDuplicate(data);
  }
}
