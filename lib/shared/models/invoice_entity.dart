import 'package:equatable/equatable.dart';

enum SyncStatus { pending, uploading, uploaded, failed }

enum ApprovalStatus { pending, uploaded, approved, rejected, returned }

enum NotificationType {
  billApproved,
  billRejected,
  billReturned,
  companyAnnouncement,
  appUpdate,
}

class InvoiceFieldData extends Equatable {
  const InvoiceFieldData({
    this.vendorName,
    this.gstin,
    this.invoiceNumber,
    this.invoiceDate,
    this.taxableValue,
    this.cgst,
    this.sgst,
    this.igst,
    this.discount,
    this.netAmount,
    this.expenseCategoryId,
    this.expenseCategoryName,
    this.remarks,
    this.supplierPhone,
    this.supplierEmail,
  });

  final String? vendorName;
  final String? gstin;
  final String? invoiceNumber;
  final DateTime? invoiceDate;
  final double? taxableValue;
  final double? cgst;
  final double? sgst;
  final double? igst;
  final double? discount;
  final double? netAmount;
  final String? expenseCategoryId;
  final String? expenseCategoryName;
  final String? remarks;
  final String? supplierPhone;
  final String? supplierEmail;

  InvoiceFieldData copyWith({
    String? vendorName,
    String? gstin,
    String? invoiceNumber,
    DateTime? invoiceDate,
    double? taxableValue,
    double? cgst,
    double? sgst,
    double? igst,
    double? discount,
    double? netAmount,
    String? expenseCategoryId,
    String? expenseCategoryName,
    String? remarks,
    String? supplierPhone,
    String? supplierEmail,
  }) {
    return InvoiceFieldData(
      vendorName: vendorName ?? this.vendorName,
      gstin: gstin ?? this.gstin,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      taxableValue: taxableValue ?? this.taxableValue,
      cgst: cgst ?? this.cgst,
      sgst: sgst ?? this.sgst,
      igst: igst ?? this.igst,
      discount: discount ?? this.discount,
      netAmount: netAmount ?? this.netAmount,
      expenseCategoryId: expenseCategoryId ?? this.expenseCategoryId,
      expenseCategoryName: expenseCategoryName ?? this.expenseCategoryName,
      remarks: remarks ?? this.remarks,
      supplierPhone: supplierPhone ?? this.supplierPhone,
      supplierEmail: supplierEmail ?? this.supplierEmail,
    );
  }

  Map<String, dynamic> toJson() => {
    'vendorName': vendorName,
    'gstin': gstin,
    'invoiceNumber': invoiceNumber,
    'invoiceDate': invoiceDate?.toIso8601String(),
    'taxableValue': taxableValue,
    'cgst': cgst,
    'sgst': sgst,
    'igst': igst,
    'discount': discount,
    'netAmount': netAmount,
    'expenseCategoryId': expenseCategoryId,
    'expenseCategoryName': expenseCategoryName,
    'remarks': remarks,
    'supplierPhone': supplierPhone,
    'supplierEmail': supplierEmail,
  };

  factory InvoiceFieldData.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const InvoiceFieldData();
    return InvoiceFieldData(
      vendorName: json['vendorName'] as String?,
      gstin: json['gstin'] as String?,
      invoiceNumber: json['invoiceNumber'] as String?,
      invoiceDate: json['invoiceDate'] is String
          ? DateTime.tryParse(json['invoiceDate'] as String)
          : null,
      // Admin edits use taxableAmount / totalAmount.
      taxableValue: _num(json['taxableValue'] ?? json['taxableAmount']),
      cgst: _num(json['cgst']),
      sgst: _num(json['sgst']),
      igst: _num(json['igst']),
      discount: _num(json['discount']),
      netAmount: _num(json['netAmount'] ?? json['totalAmount']),
      expenseCategoryId: json['expenseCategoryId'] as String?,
      expenseCategoryName: json['expenseCategoryName'] as String?,
      remarks: json['remarks'] as String?,
      supplierPhone: json['supplierPhone'] as String?,
      supplierEmail: json['supplierEmail'] as String?,
    );
  }

  /// Amounts may arrive as numbers or decimal strings.
  static double? _num(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', ''));
    return null;
  }

  @override
  List<Object?> get props => [
    vendorName,
    gstin,
    invoiceNumber,
    invoiceDate,
    taxableValue,
    cgst,
    sgst,
    igst,
    discount,
    netAmount,
    expenseCategoryId,
    expenseCategoryName,
    remarks,
    supplierPhone,
    supplierEmail,
  ];
}

class InvoiceEntity extends Equatable {
  const InvoiceEntity({
    required this.localId,
    required this.companyId,
    required this.employeeId,
    required this.branchId,
    required this.deviceId,
    required this.createdAt,
    required this.syncStatus,
    required this.approvalStatus,
    required this.ocrData,
    required this.editedData,
    required this.ocrConfidence,
    this.serverId,
    this.originalImagePath,
    this.compressedImagePath,
    this.thumbnailPath,
    this.latitude,
    this.longitude,
    this.uploadAttempts = 0,
    this.lastUploadError,
    this.idempotencyKey,
    this.adminRemarks,
    this.uploadedAt,
    this.duplicateOverride = false,
    this.uploadErrorCode,
    this.imageUrl,
    this.thumbnailUrl,
  });

  /// Upload error codes that need the employee to act (no auto-retry).
  static const errorDuplicate = 'duplicate';
  static const errorRejected = 'rejected';

  final String localId;
  final String? serverId;
  final String companyId;
  final String employeeId;
  final String branchId;
  final String deviceId;
  final DateTime createdAt;
  final DateTime? uploadedAt;
  final SyncStatus syncStatus;
  final ApprovalStatus approvalStatus;
  final InvoiceFieldData ocrData;
  final InvoiceFieldData editedData;
  final double ocrConfidence;
  final String? originalImagePath;
  final String? compressedImagePath;
  final String? thumbnailPath;
  final double? latitude;
  final double? longitude;
  final int uploadAttempts;
  final String? lastUploadError;
  final String? idempotencyKey;
  final String? adminRemarks;
  final bool duplicateOverride;
  final String? uploadErrorCode;

  /// Signed, short-lived server image links (history entries have no files).
  final String? imageUrl;
  final String? thumbnailUrl;

  InvoiceFieldData get displayData => editedData;

  /// Imported from server history; there are no local files to upload.
  bool get isServerOnly =>
      serverId != null &&
      originalImagePath == null &&
      compressedImagePath == null &&
      thumbnailPath == null;

  /// Not yet on the server, so it can be discarded from this device.
  bool get canDeleteLocally =>
      serverId == null && syncStatus != SyncStatus.uploading;

  bool get needsDuplicateOverride =>
      syncStatus == SyncStatus.failed && uploadErrorCode == errorDuplicate;

  bool get canResubmit =>
      serverId != null && approvalStatus == ApprovalStatus.returned;

  /// [clearUploadError] resets the error message and code, which a plain
  /// `null` argument cannot do.
  InvoiceEntity copyWith({
    String? serverId,
    SyncStatus? syncStatus,
    ApprovalStatus? approvalStatus,
    InvoiceFieldData? ocrData,
    InvoiceFieldData? editedData,
    double? ocrConfidence,
    String? originalImagePath,
    String? compressedImagePath,
    String? thumbnailPath,
    double? latitude,
    double? longitude,
    int? uploadAttempts,
    String? lastUploadError,
    String? idempotencyKey,
    String? adminRemarks,
    DateTime? uploadedAt,
    bool? duplicateOverride,
    String? branchId,
    String? uploadErrorCode,
    String? imageUrl,
    String? thumbnailUrl,
    bool clearUploadError = false,
    bool clearOriginalImage = false,
  }) {
    return InvoiceEntity(
      localId: localId,
      serverId: serverId ?? this.serverId,
      companyId: companyId,
      employeeId: employeeId,
      branchId: branchId ?? this.branchId,
      deviceId: deviceId,
      createdAt: createdAt,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      ocrData: ocrData ?? this.ocrData,
      editedData: editedData ?? this.editedData,
      ocrConfidence: ocrConfidence ?? this.ocrConfidence,
      originalImagePath: clearOriginalImage
          ? null
          : originalImagePath ?? this.originalImagePath,
      compressedImagePath: compressedImagePath ?? this.compressedImagePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      uploadAttempts: uploadAttempts ?? this.uploadAttempts,
      lastUploadError: clearUploadError
          ? null
          : lastUploadError ?? this.lastUploadError,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      adminRemarks: adminRemarks ?? this.adminRemarks,
      duplicateOverride: duplicateOverride ?? this.duplicateOverride,
      uploadErrorCode: clearUploadError
          ? null
          : uploadErrorCode ?? this.uploadErrorCode,
      imageUrl: imageUrl ?? this.imageUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
    );
  }

  /// A read-only entry built from a `GET /invoices/mine` or
  /// `GET /invoices/{id}` summary (e.g. history after a reinstall).
  factory InvoiceEntity.fromServer(
    Map<String, dynamic> item, {
    required String companyId,
    required String employeeId,
  }) {
    final serverId = item['id'] as String;
    final key = item['localIdempotencyKey'] as String?;
    final edited = InvoiceFieldData.fromJson(
      (item['editedData'] as Map?)?.cast<String, dynamic>(),
    );
    final uploadedAt = item['uploadedAt'] is String
        ? DateTime.tryParse(item['uploadedAt'] as String)?.toLocal()
        : null;
    return InvoiceEntity(
      localId: 'srv_$serverId',
      serverId: serverId,
      companyId: companyId,
      employeeId: employeeId,
      branchId: item['branchId'] as String? ?? '',
      deviceId: item['deviceId'] as String? ?? '',
      createdAt: uploadedAt ?? DateTime.now(),
      uploadedAt: uploadedAt,
      syncStatus: SyncStatus.uploaded,
      approvalStatus:
          approvalStatusFromApi(item['approvalStatus'] as String?) ??
              ApprovalStatus.uploaded,
      ocrData: InvoiceFieldData.fromJson(
        (item['ocrData'] as Map?)?.cast<String, dynamic>(),
      ),
      editedData: mergeServerFields(edited, item),
      ocrConfidence: 0,
      idempotencyKey: key,
      adminRemarks: item['adminRemarks'] as String?,
      imageUrl: item['imageUrl'] as String?,
      thumbnailUrl: item['thumbnailUrl'] as String?,
    );
  }

  /// Fills gaps in [data] from the server's normalised top-level columns.
  static InvoiceFieldData mergeServerFields(
    InvoiceFieldData data,
    Map<String, dynamic> item,
  ) {
    final date = item['invoiceDate'];
    final net = item['netAmount'];
    return InvoiceFieldData(
      vendorName: data.vendorName ?? item['vendorName'] as String?,
      gstin: data.gstin ?? item['gstin'] as String?,
      invoiceNumber: data.invoiceNumber ?? item['invoiceNumber'] as String?,
      invoiceDate:
          data.invoiceDate ?? (date is String ? DateTime.tryParse(date) : null),
      taxableValue: data.taxableValue,
      cgst: data.cgst,
      sgst: data.sgst,
      igst: data.igst,
      discount: data.discount,
      netAmount: data.netAmount ??
          (net is num ? net.toDouble() : double.tryParse('${net ?? ''}')),
      expenseCategoryId:
          data.expenseCategoryId ?? item['categoryId'] as String?,
      expenseCategoryName:
          data.expenseCategoryName ?? item['categoryName'] as String?,
      remarks: data.remarks,
      supplierPhone: data.supplierPhone,
      supplierEmail: data.supplierEmail,
    );
  }

  Map<String, dynamic> toJson() => {
    'localId': localId,
    'serverId': serverId,
    'companyId': companyId,
    'employeeId': employeeId,
    'branchId': branchId,
    'deviceId': deviceId,
    'createdAt': createdAt.toIso8601String(),
    'uploadedAt': uploadedAt?.toIso8601String(),
    'syncStatus': syncStatus.name,
    'approvalStatus': approvalStatus.name,
    'ocrData': ocrData.toJson(),
    'editedData': editedData.toJson(),
    'ocrConfidence': ocrConfidence,
    'originalImagePath': originalImagePath,
    'compressedImagePath': compressedImagePath,
    'thumbnailPath': thumbnailPath,
    'latitude': latitude,
    'longitude': longitude,
    'uploadAttempts': uploadAttempts,
    'lastUploadError': lastUploadError,
    'idempotencyKey': idempotencyKey,
    'adminRemarks': adminRemarks,
    'duplicateOverride': duplicateOverride,
    'uploadErrorCode': uploadErrorCode,
    'imageUrl': imageUrl,
    'thumbnailUrl': thumbnailUrl,
  };

  factory InvoiceEntity.fromJson(Map<String, dynamic> json) {
    return InvoiceEntity(
      localId: json['localId'] as String,
      serverId: json['serverId'] as String?,
      companyId: json['companyId'] as String,
      employeeId: json['employeeId'] as String,
      branchId: json['branchId'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      uploadedAt: json['uploadedAt'] != null
          ? DateTime.tryParse(json['uploadedAt'] as String)
          : null,
      syncStatus: SyncStatus.values.byName(json['syncStatus'] as String),
      approvalStatus: ApprovalStatus.values.byName(
        json['approvalStatus'] as String,
      ),
      ocrData: InvoiceFieldData.fromJson(
        (json['ocrData'] as Map?)?.cast<String, dynamic>(),
      ),
      editedData: InvoiceFieldData.fromJson(
        (json['editedData'] as Map?)?.cast<String, dynamic>(),
      ),
      ocrConfidence: (json['ocrConfidence'] as num?)?.toDouble() ?? 0,
      originalImagePath: json['originalImagePath'] as String?,
      compressedImagePath: json['compressedImagePath'] as String?,
      thumbnailPath: json['thumbnailPath'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      uploadAttempts: json['uploadAttempts'] as int? ?? 0,
      lastUploadError: json['lastUploadError'] as String?,
      idempotencyKey: json['idempotencyKey'] as String?,
      adminRemarks: json['adminRemarks'] as String?,
      duplicateOverride: json['duplicateOverride'] as bool? ?? false,
      uploadErrorCode: json['uploadErrorCode'] as String?,
      imageUrl: json['imageUrl'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
    );
  }

  @override
  List<Object?> get props => [
    localId,
    serverId,
    syncStatus,
    approvalStatus,
    editedData,
    adminRemarks,
    lastUploadError,
  ];
}

/// Maps the API's `approvalStatus`; the server's `pending` means submitted.
ApprovalStatus? approvalStatusFromApi(String? value) {
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
