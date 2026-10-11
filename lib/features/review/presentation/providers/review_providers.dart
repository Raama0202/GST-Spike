import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/models/invoice_entity.dart';

/// Draft invoice assembled during scan → OCR → review.
class ReviewDraft {
  const ReviewDraft({
    this.localId,
    this.sourceImagePath,
    this.originalImagePath,
    this.compressedImagePath,
    this.thumbnailPath,
    this.ocrData = const InvoiceFieldData(),
    this.editedData = const InvoiceFieldData(),
    this.ocrConfidence = 0,
    this.rawOcrText,
    this.isBlurry = false,
    this.blurVariance = 0,
    this.latitude,
    this.longitude,
    this.duplicateOverride = false,
  });

  final String? localId;
  final String? sourceImagePath;
  final String? originalImagePath;
  final String? compressedImagePath;
  final String? thumbnailPath;
  final InvoiceFieldData ocrData;
  final InvoiceFieldData editedData;
  final double ocrConfidence;
  final String? rawOcrText;
  final bool isBlurry;
  final double blurVariance;
  final double? latitude;
  final double? longitude;
  final bool duplicateOverride;

  bool get hasImage =>
      compressedImagePath != null ||
      originalImagePath != null ||
      sourceImagePath != null;

  ReviewDraft copyWith({
    String? localId,
    String? sourceImagePath,
    String? originalImagePath,
    String? compressedImagePath,
    String? thumbnailPath,
    InvoiceFieldData? ocrData,
    InvoiceFieldData? editedData,
    double? ocrConfidence,
    String? rawOcrText,
    bool? isBlurry,
    double? blurVariance,
    double? latitude,
    double? longitude,
    bool? duplicateOverride,
  }) {
    return ReviewDraft(
      localId: localId ?? this.localId,
      sourceImagePath: sourceImagePath ?? this.sourceImagePath,
      originalImagePath: originalImagePath ?? this.originalImagePath,
      compressedImagePath: compressedImagePath ?? this.compressedImagePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      ocrData: ocrData ?? this.ocrData,
      editedData: editedData ?? this.editedData,
      ocrConfidence: ocrConfidence ?? this.ocrConfidence,
      rawOcrText: rawOcrText ?? this.rawOcrText,
      isBlurry: isBlurry ?? this.isBlurry,
      blurVariance: blurVariance ?? this.blurVariance,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      duplicateOverride: duplicateOverride ?? this.duplicateOverride,
    );
  }
}

class ReviewDraftNotifier extends StateNotifier<ReviewDraft?> {
  ReviewDraftNotifier() : super(null);

  void startCapture(String sourceImagePath) {
    state = ReviewDraft(sourceImagePath: sourceImagePath);
  }

  void setProcessedImages({
    required String originalImagePath,
    required String compressedImagePath,
    required String thumbnailPath,
    required bool isBlurry,
    required double blurVariance,
  }) {
    if (state == null) return;
    state = state!.copyWith(
      originalImagePath: originalImagePath,
      compressedImagePath: compressedImagePath,
      thumbnailPath: thumbnailPath,
      isBlurry: isBlurry,
      blurVariance: blurVariance,
    );
  }

  void setOcrResult({
    required InvoiceFieldData ocrData,
    required InvoiceFieldData editedData,
    required double ocrConfidence,
    required String rawOcrText,
  }) {
    if (state == null) return;
    state = state!.copyWith(
      ocrData: ocrData,
      editedData: editedData,
      ocrConfidence: ocrConfidence,
      rawOcrText: rawOcrText,
    );
  }

  void updateEditedData(InvoiceFieldData editedData) {
    if (state == null) return;
    state = state!.copyWith(editedData: editedData);
  }

  void setLocation({double? latitude, double? longitude}) {
    if (state == null) return;
    state = state!.copyWith(latitude: latitude, longitude: longitude);
  }

  void setLocalId(String localId) {
    if (state == null) return;
    state = state!.copyWith(localId: localId);
  }

  void setDuplicateOverride(bool value) {
    if (state == null) return;
    state = state!.copyWith(duplicateOverride: value);
  }

  void clear() => state = null;
}

final reviewDraftProvider =
    StateNotifierProvider<ReviewDraftNotifier, ReviewDraft?>(
  (ref) => ReviewDraftNotifier(),
);

final reviewHasDraftProvider = Provider<bool>((ref) {
  return ref.watch(reviewDraftProvider) != null;
});

final reviewLowConfidenceProvider = Provider<bool>((ref) {
  final draft = ref.watch(reviewDraftProvider);
  if (draft == null) return false;
  return draft.ocrConfidence < AppConstants.lowOcrConfidenceThreshold;
});
