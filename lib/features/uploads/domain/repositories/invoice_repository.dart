import '../../../../shared/models/invoice_entity.dart';

/// Result of a duplicate invoice lookup.
class DuplicateCheckResult {
  const DuplicateCheckResult({
    required this.isDuplicate,
    this.existingLocalId,
    this.existingServerId,
    this.source,
    this.message,
    this.checked = true,
  });

  /// The server could not be asked (offline, timeout, outage). Saving must
  /// go ahead; the server re-checks when the queued upload arrives.
  const DuplicateCheckResult.unknown()
      : isDuplicate = false,
        existingLocalId = null,
        existingServerId = null,
        source = 'unknown',
        message = null,
        checked = false;

  final bool isDuplicate;
  final String? existingLocalId;
  final String? existingServerId;
  final String? source;
  final String? message;
  final bool checked;
}

/// One entry of an invoice's audit trail (`history` on `GET /invoices/{id}`).
class InvoiceHistoryEntry {
  const InvoiceHistoryEntry({
    required this.action,
    this.remarks,
    this.byName,
    this.at,
  });

  final String action;
  final String? remarks;
  final String? byName;
  final DateTime? at;

  factory InvoiceHistoryEntry.fromJson(Map<String, dynamic> json) {
    final at = json['at'];
    return InvoiceHistoryEntry(
      action: json['action']?.toString() ?? '',
      remarks: json['remarks'] as String?,
      byName: json['byName'] as String?,
      at: at is String ? DateTime.tryParse(at)?.toLocal() : null,
    );
  }
}

/// Server view of one invoice, with a fresh image link and history.
class ServerInvoiceDetail {
  const ServerInvoiceDetail({
    required this.invoice,
    this.history = const [],
  });

  final InvoiceEntity invoice;
  final List<InvoiceHistoryEntry> history;
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
    String? localId,
    double? latitude,
    double? longitude,
    bool duplicateOverride = false,
  });

  Future<InvoiceEntity> updateEdited({
    required String localId,
    required InvoiceFieldData editedData,
    bool duplicateOverride = false,
  });

  Future<void> enqueue(String localId);

  Future<List<InvoiceEntity>> list({SyncStatus? syncStatus});

  Future<InvoiceEntity?> getById(String localId);

  Future<InvoiceEntity?> getByServerId(String serverId);

  Future<DuplicateCheckResult> checkDuplicate(
    InvoiceFieldData data, {
    String? excludeLocalId,
  });

  /// Removes an invoice that never reached the server, with its images.
  Future<void> deleteLocal(String localId);

  /// Puts a failed invoice back in the queue with a fresh attempt budget.
  Future<void> retryNow(String localId, {bool duplicateOverride = false});

  /// Fetches `GET /invoices/{id}` and caches it locally when unknown.
  Future<ServerInvoiceDetail> fetchServerInvoice(String serverId);

  /// Sends edits for a returned invoice; returns the updated local entry.
  Future<InvoiceEntity> resubmit({
    required InvoiceEntity invoice,
    required InvoiceFieldData editedData,
    String? note,
  });
}
