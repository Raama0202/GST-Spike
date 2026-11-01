import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/network/api_client.dart';
import '../../../../shared/models/invoice_entity.dart';
import 'ocr_result.dart';

/// Calls the backend Gemini vision extractor when the device is online.
class AiInvoiceExtractRemoteDataSource {
  AiInvoiceExtractRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  static const _extractMaxSide = 1600;
  static bool? _available;
  static DateTime _availableCheckedAt = DateTime(0);

  /// Cached so each scan does not pay an extra round trip; a negative answer
  /// is re-checked sooner because it is usually just a lost connection.
  Future<bool> isAvailable() async {
    final cached = _available;
    final age = DateTime.now().difference(_availableCheckedAt);
    if (cached != null &&
        age < (cached ? const Duration(minutes: 10) : const Duration(minutes: 1))) {
      return cached;
    }
    bool available;
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        ApiEndpoints.invoiceExtractStatus,
      );
      available = response.data?['available'] == true;
    } catch (_) {
      available = false;
    }
    _available = available;
    _availableCheckedAt = DateTime.now();
    return available;
  }

  /// The extractor reads text fine at 1600 px; full camera frames are
  /// 3–8 MB and make the request slow on mobile data.
  Future<MultipartFile> _downscaled(String imagePath) async {
    try {
      final bytes = await FlutterImageCompress.compressWithFile(
        imagePath,
        minWidth: _extractMaxSide,
        minHeight: _extractMaxSide,
        quality: 85,
        format: CompressFormat.jpeg,
      );
      if (bytes != null && bytes.isNotEmpty) {
        return MultipartFile.fromBytes(
          bytes,
          filename: 'invoice.jpg',
          contentType: DioMediaType.parse('image/jpeg'),
        );
      }
    } catch (_) {}
    return MultipartFile.fromFile(
      imagePath,
      filename: 'invoice.jpg',
      contentType: DioMediaType.parse('image/jpeg'),
    );
  }

  Future<OcrRunResult> extract(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw AppException(
        OcrFailure('Image not found for AI extraction: $imagePath'),
      );
    }

    try {
      final formData = FormData.fromMap({
        'image': await _downscaled(imagePath),
      });

      final response = await _apiClient.uploadMultipart<Map<String, dynamic>>(
        ApiEndpoints.invoiceExtract,
        formData: formData,
        options: Options(
          contentType: 'multipart/form-data',
          sendTimeout: const Duration(seconds: 90),
          receiveTimeout: const Duration(seconds: 90),
        ),
      );

      final body = response.data ?? const <String, dynamic>{};
      final data = InvoiceFieldData.fromJson(body);
      final confidence = (body['confidence'] as num?)?.toDouble() ?? 0.7;
      final provider = body['provider']?.toString() ?? 'ai';
      final notes = body['notes']?.toString();

      return OcrRunResult(
        data: data,
        confidence: confidence.clamp(0.0, 1.0),
        rawText: [
          'Extracted by $provider',
          if (notes != null && notes.isNotEmpty) 'Notes: $notes',
          'Fields: ${data.toJson()}',
        ].join('\n'),
        source: OcrExtractionSource.ai,
      );
    } on AppException {
      rethrow;
    } catch (error) {
      throw AppException(
        OcrFailure('AI extraction failed: $error'),
      );
    }
  }
}
