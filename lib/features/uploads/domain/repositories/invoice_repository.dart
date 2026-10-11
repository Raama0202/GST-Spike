import '../../../../shared/models/invoice_entity.dart';

/// Result of a duplicate invoice lookup.
class DuplicateCheckResult {
  const DuplicateCheckResult({
    required this.isDuplicate,
    this.existingLocalId,
    this.existingServerId,
    this.source,
    this.message,
  });

  final bool isDuplicate;
  final String? existingLocalId;
  final String? existingServerId;
  final String? source;
  final String? message;
}

/// Contract for local and remote invoice persistence.
abstract class InvoiceRepository {
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
  });

  Future<InvoiceEntity> updateEdited({
    required String localId,
    required InvoiceFieldData editedData,
    bool duplicateOverride = false,
  });

  Future<void> enqueue(String localId);

  Future<List<InvoiceEntity>> list({SyncStatus? syncStatus});

  Future<InvoiceEntity?> getById(String localId);

  Future<DuplicateCheckResult> checkDuplicate(
    InvoiceFieldData data, {
    String? excludeLocalId,
  });
}
