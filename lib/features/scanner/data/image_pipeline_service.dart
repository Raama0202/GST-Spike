import 'dart:io';
import 'dart:isolate';
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

    // The "original" is a 2048 px high-quality JPEG rather than the raw camera
    // file: sharp enough for AI reading of small handwriting, but a fraction
    // of a 12 MP photo's size in upload bandwidth and database storage.
    final bounded = await _boundedJpeg(sourcePath);
    final originalFile = await _imageStore.originalFile(localId);
    await originalFile.writeAsBytes(bounded, flush: true);

    final enhancedBytes = await _enhanceBounded(bounded, sourcePath);
    final blurVariance = await Isolate.run(
      () => _laplacianVariance(enhancedBytes),
    );
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
    final bytes = await _boundedJpeg(imagePath);
    final variance = await Isolate.run(() => _laplacianVariance(bytes));
    return variance < AppConstants.blurVarianceThreshold;
  }

  /// Camera scans can be 12+ MP; decoding those in Dart on the UI isolate
  /// freezes the app and can run it out of memory. Downscale natively first,
  /// then do the pixel work on a background isolate.
  Future<Uint8List> _enhance(String imagePath) async {
    return _enhanceBounded(await _boundedJpeg(imagePath), imagePath);
  }

  Future<Uint8List> _enhanceBounded(Uint8List bounded, String imagePath) async {
    final enhanced = await Isolate.run(() => _enhanceBytes(bounded));
    if (enhanced == null) {
      throw AppException(
        StorageFailure('Unable to decode image at $imagePath'),
      );
    }
    return enhanced;
  }

  Future<Uint8List> _boundedJpeg(String imagePath) async {
    Uint8List? bounded;
    try {
      bounded = await FlutterImageCompress.compressWithFile(
        imagePath,
        minWidth: _maxWorkingEdge,
        minHeight: _maxWorkingEdge,
        quality: 95,
        format: CompressFormat.jpeg,
      );
    } catch (_) {
      bounded = null;
    }
    return bounded ?? await File(imagePath).readAsBytes();
  }

  static const int _maxWorkingEdge = 2048;
  static const int _blurAnalysisEdge = 1024;

  static Uint8List? _enhanceBytes(Uint8List bytes) {
    var decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final longest = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;
    if (longest > _maxWorkingEdge) {
      decoded = decoded.width >= decoded.height
          ? img.copyResize(decoded, width: _maxWorkingEdge)
          : img.copyResize(decoded, height: _maxWorkingEdge);
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

  static double _laplacianVariance(Uint8List bytes) {
    var decoded = img.decodeImage(bytes);
    if (decoded == null) return 0;
    if (decoded.width > _blurAnalysisEdge) {
      decoded = img.copyResize(decoded, width: _blurAnalysisEdge);
    }

    final gray = img.grayscale(decoded);
    final width = gray.width;
    final height = gray.height;
    if (width < 3 || height < 3) return 0;

    var count = 0;
    var sum = 0.0;
    var sumSq = 0.0;
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final center = gray.getPixel(x, y).r.toDouble();
        final top = gray.getPixel(x, y - 1).r.toDouble();
        final bottom = gray.getPixel(x, y + 1).r.toDouble();
        final left = gray.getPixel(x - 1, y).r.toDouble();
        final right = gray.getPixel(x + 1, y).r.toDouble();
        final value = -4 * center + top + bottom + left + right;
        sum += value;
        sumSq += value * value;
        count++;
      }
    }

    if (count == 0) return 0;
    final mean = sum / count;
    return sumSq / count - mean * mean;
  }
}
