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
      invoiceDate: json['invoiceDate'] != null
          ? DateTime.tryParse(json['invoiceDate'] as String)
          : null,
      taxableValue: (json['taxableValue'] as num?)?.toDouble(),
      cgst: (json['cgst'] as num?)?.toDouble(),
      sgst: (json['sgst'] as num?)?.toDouble(),
      igst: (json['igst'] as num?)?.toDouble(),
      discount: (json['discount'] as num?)?.toDouble(),
      netAmount: (json['netAmount'] as num?)?.toDouble(),
      expenseCategoryId: json['expenseCategoryId'] as String?,
      expenseCategoryName: json['expenseCategoryName'] as String?,
      remarks: json['remarks'] as String?,
      supplierPhone: json['supplierPhone'] as String?,
      supplierEmail: json['supplierEmail'] as String?,
    );
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
  });

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

  InvoiceFieldData get displayData => editedData;

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
      originalImagePath: originalImagePath ?? this.originalImagePath,
      compressedImagePath: compressedImagePath ?? this.compressedImagePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      uploadAttempts: uploadAttempts ?? this.uploadAttempts,
      lastUploadError: lastUploadError ?? this.lastUploadError,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      adminRemarks: adminRemarks ?? this.adminRemarks,
      duplicateOverride: duplicateOverride ?? this.duplicateOverride,
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
    );
  }

  @override
  List<Object?> get props => [localId, syncStatus, approvalStatus, editedData];
}
