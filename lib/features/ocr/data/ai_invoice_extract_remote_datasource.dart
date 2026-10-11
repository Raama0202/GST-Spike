import 'dart:io';

import 'package:dio/dio.dart';

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

  Future<bool> isAvailable() async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        ApiEndpoints.invoiceExtractStatus,
      );
      return response.data?['available'] == true;
    } catch (_) {
      return false;
    }
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
        'image': await MultipartFile.fromFile(
          imagePath,
          filename: 'invoice.jpg',
          contentType: DioMediaType.parse('image/jpeg'),
        ),
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
