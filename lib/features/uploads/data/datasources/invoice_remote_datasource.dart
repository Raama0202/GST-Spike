import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/network/api_client.dart';
import '../../../../shared/models/invoice_entity.dart';
import '../../domain/repositories/invoice_repository.dart';

/// Remote invoice duplicate check and multipart upload.
class InvoiceRemoteDataSource {
  InvoiceRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<DuplicateCheckResult> checkDuplicate(InvoiceFieldData data) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        ApiEndpoints.invoiceDuplicateCheck,
        data: {
          'gstin': data.gstin,
          'invoiceNumber': data.invoiceNumber,
          'invoiceDate': data.invoiceDate?.toIso8601String().substring(0, 10),
          'netAmount': data.netAmount,
        },
      );

      final body = response.data ?? const {};
      return DuplicateCheckResult(
        isDuplicate: body['isDuplicate'] == true ||
            body['duplicate'] == true,
        existingServerId: body['matchedInvoiceId'] as String?,
        source: 'remote',
        message: body['message'] as String?,
      );
    } on AppException {
      rethrow;
    } catch (error) {
      throw AppException(
        ServerFailure('Duplicate check failed: $error'),
      );
    }
  }

  Future<String> uploadInvoice({
    required InvoiceEntity invoice,
    required String imagePath,
    ProgressCallback? onSendProgress,
  }) async {
    final imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      throw AppException(
        StorageFailure('Upload image missing at $imagePath'),
      );
    }

    // The API stores three renditions; reuse whichever the pipeline produced so
    // an older queued invoice with only one file still uploads.
    final original = await _resolveImage(
      [invoice.originalImagePath, invoice.compressedImagePath, imagePath],
      imagePath,
    );
    final compressed = await _resolveImage(
      [invoice.compressedImagePath, imagePath, invoice.originalImagePath],
      imagePath,
    );
    final thumbnail = await _resolveImage(
      [invoice.thumbnailPath, invoice.compressedImagePath, imagePath],
      imagePath,
    );

    try {
      final formData = FormData.fromMap({
        'idempotencyKey': invoice.idempotencyKey ?? invoice.localId,
        'payload': _encodeInvoicePayload(invoice),
        'original': await MultipartFile.fromFile(
          original,
          filename: 'original.jpg',
          contentType: DioMediaType.parse('image/jpeg'),
        ),
        'compressed': await MultipartFile.fromFile(
          compressed,
          filename: 'compressed.jpg',
          contentType: DioMediaType.parse('image/jpeg'),
        ),
        'thumbnail': await MultipartFile.fromFile(
          thumbnail,
          filename: 'thumbnail.jpg',
          contentType: DioMediaType.parse('image/jpeg'),
        ),
      });

      final response = await _apiClient.uploadMultipart<Map<String, dynamic>>(
        ApiEndpoints.invoiceUpload,
        formData: formData,
        onSendProgress: onSendProgress,
      );

      final body = response.data ?? const {};
      final serverId = body['id'] as String? ??
          body['serverId'] as String? ??
          body['invoiceId'] as String?;

      if (serverId == null || serverId.isEmpty) {
        throw AppException(
          const ServerFailure('Upload succeeded but server id was missing.'),
        );
      }

      return serverId;
    } on AppException {
      rethrow;
    } catch (error) {
      throw AppException(
        ServerFailure('Invoice upload failed: $error'),
      );
    }
  }

  /// Server-side state of this employee's invoices (admin decisions).
  Future<List<Map<String, dynamic>>> fetchMine({int pageSize = 100}) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.myInvoices,
      queryParameters: {'page': 1, 'pageSize': pageSize},
    );
    final items = response.data?['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<String> _resolveImage(
    List<String?> candidates,
    String fallback,
  ) async {
    for (final candidate in candidates) {
      if (candidate == null || candidate.isEmpty) continue;
      if (await File(candidate).exists()) return candidate;
    }
    return fallback;
  }

  /// Matches the API's `InvoicePayload`; identifiers the server rejects when
  /// blank or non-UUID are omitted rather than sent empty.
  String _encodeInvoicePayload(InvoiceEntity invoice) {
    final branchId = _uuidOrNull(invoice.branchId);
    final categoryId = _uuidOrNull(invoice.editedData.expenseCategoryId) ??
        _uuidOrNull(invoice.ocrData.expenseCategoryId);

    final payload = <String, dynamic>{
      'branchId': ?branchId,
      'categoryId': ?categoryId,
      if (invoice.deviceId.isNotEmpty) 'deviceId': invoice.deviceId,
      'latitude': ?invoice.latitude,
      'longitude': ?invoice.longitude,
      'ocrConfidence': invoice.ocrConfidence,
      'ocrData': invoice.ocrData.toJson(),
      'editedData': invoice.editedData.toJson(),
      'duplicateOverride': invoice.duplicateOverride,
    };
    return jsonEncode(payload);
  }

  static final _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  String? _uuidOrNull(String? value) {
    if (value == null || value.isEmpty) return null;
    return _uuidPattern.hasMatch(value) ? value : null;
  }
}
