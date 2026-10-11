import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/errors/failures.dart';
import '../../../core/storage/local_database.dart';

/// Output of the invoice image processing pipeline.
class ProcessedImagePaths {
  const ProcessedImagePaths({
    required this.originalPath,
    required this.compressedPath,
    required this.thumbnailPath,
    required this.isBlurry,
    required this.blurVariance,
  });

  final String originalPath;
  final String compressedPath;
  final String thumbnailPath;
  final bool isBlurry;
  final double blurVariance;
}

/// Saves, enhances, compresses, and thumbnails invoice capture images.
class ImagePipelineService {
  ImagePipelineService({InvoiceImageStore? imageStore})
      : _imageStore = imageStore ?? InvoiceImageStore();

  final InvoiceImageStore _imageStore;

  Future<ProcessedImagePaths> process({
    required String sourcePath,
    required String localId,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw AppException(
        StorageFailure('Source image not found at $sourcePath'),
      );
    }

    await _imageStore.ensureInvoiceDir(localId);

    final originalFile = await _imageStore.originalFile(localId);
    await source.copy(originalFile.path);

    final enhancedBytes = await _enhance(originalFile.path);
    final blurVariance = _laplacianVariance(enhancedBytes);
    final isBlurry = blurVariance < AppConstants.blurVarianceThreshold;

    final compressedFile = await _imageStore.compressedFile(localId);
    await _compressToTarget(
      sourceBytes: enhancedBytes,
      outputPath: compressedFile.path,
    );

    final thumbnailFile = await _imageStore.thumbnailFile(localId);
    await _createThumbnail(
      sourceBytes: enhancedBytes,
      outputPath: thumbnailFile.path,
    );

    return ProcessedImagePaths(
      originalPath: originalFile.path,
      compressedPath: compressedFile.path,
      thumbnailPath: thumbnailFile.path,
      isBlurry: isBlurry,
      blurVariance: blurVariance,
    );
  }

  Future<File> saveOriginal({
    required String sourcePath,
    required String localId,
  }) async {
    await _imageStore.ensureInvoiceDir(localId);
    final originalFile = await _imageStore.originalFile(localId);
    await File(sourcePath).copy(originalFile.path);
    return originalFile;
  }

  Future<Uint8List> enhance(String imagePath) async {
    return _enhance(imagePath);
  }

  Future<bool> isBlurry(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final variance = _laplacianVariance(bytes);
    return variance < AppConstants.blurVarianceThreshold;
  }

  Future<Uint8List> _enhance(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw AppException(
        StorageFailure('Unable to decode image at $imagePath'),
      );
    }

    final enhanced = img.adjustColor(
      decoded,
      contrast: 1.12,
      brightness: 1.02,
    );
    return Uint8List.fromList(img.encodeJpg(enhanced, quality: 92));
  }

  Future<void> _compressToTarget({
    required Uint8List sourceBytes,
    required String outputPath,
  }) async {
    var quality = 88;
    Uint8List? result;

    while (quality >= 40) {
      result = await FlutterImageCompress.compressWithList(
        sourceBytes,
        minWidth: 2048,
        minHeight: 2048,
        quality: quality,
        format: CompressFormat.jpeg,
      );

      if (result.length <= AppConstants.maxUploadImageBytes) {
        break;
      }
      quality -= 8;
    }

    result ??= sourceBytes;
    if (result.length > AppConstants.maxUploadImageBytes) {
      result = await FlutterImageCompress.compressWithList(
        sourceBytes,
        minWidth: 1600,
        minHeight: 1600,
        quality: 40,
        format: CompressFormat.jpeg,
      );
    }

    await File(outputPath).writeAsBytes(result, flush: true);
  }

  Future<void> _createThumbnail({
    required Uint8List sourceBytes,
    required String outputPath,
  }) async {
    final thumb = await FlutterImageCompress.compressWithList(
      sourceBytes,
      minWidth: AppConstants.thumbnailMaxEdge,
      minHeight: AppConstants.thumbnailMaxEdge,
      quality: 78,
      format: CompressFormat.jpeg,
    );
    await File(outputPath).writeAsBytes(thumb, flush: true);
  }

  double _laplacianVariance(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return 0;

    final gray = img.grayscale(decoded);
    final width = gray.width;
    final height = gray.height;
    if (width < 3 || height < 3) return 0;

    final values = <double>[];
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final center = gray.getPixel(x, y).r.toDouble();
        final top = gray.getPixel(x, y - 1).r.toDouble();
        final bottom = gray.getPixel(x, y + 1).r.toDouble();
        final left = gray.getPixel(x - 1, y).r.toDouble();
        final right = gray.getPixel(x + 1, y).r.toDouble();
        values.add(-4 * center + top + bottom + left + right);
      }
    }

    if (values.isEmpty) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    var sumSq = 0.0;
    for (final value in values) {
      final delta = value - mean;
      sumSq += delta * delta;
    }
    return sumSq / values.length;
  }
}
