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

    final originalFile = await _imageStore.originalFile(localId);
    await source.copy(originalFile.path);

    // Native downscale first: decoding a full 12MP photo in Dart is the
    // slowest step of the pipeline.
    final working = await FlutterImageCompress.compressWithFile(
      originalFile.path,
      minWidth: _workingShortEdge,
      minHeight: _workingShortEdge,
      quality: 95,
      format: CompressFormat.jpeg,
    );
    final originalPath = originalFile.path;
    final (enhancedBytes, blurVariance) = await Isolate.run(() {
      final enhanced = _enhanceSync(originalPath, bytes: working);
      return (enhanced.bytes, _laplacianVarianceOf(enhanced.image));
    });
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

  Future<Uint8List> enhance(String imagePath) {
    return Isolate.run(() => _enhanceSync(imagePath).bytes);
  }

  Future<bool> isBlurry(String imagePath) async {
    final variance = await Isolate.run(() {
      final decoded = img.decodeImage(File(imagePath).readAsBytesSync());
      if (decoded == null) return 0.0;
      return _laplacianVarianceOf(_downscale(decoded));
    });
    return variance < AppConstants.blurVarianceThreshold;
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

}

/// Short edge of the working image; matches the 2048px floor the compressor
/// already produced, so OCR and upload quality are unchanged.
const _workingShortEdge = 2048;

img.Image _downscale(img.Image source) {
  final shortEdge = source.width < source.height ? source.width : source.height;
  if (shortEdge <= _workingShortEdge) return source;
  final scale = _workingShortEdge / shortEdge;
  return img.copyResize(
    source,
    width: (source.width * scale).round(),
    height: (source.height * scale).round(),
    interpolation: img.Interpolation.average,
  );
}

/// Runs off the UI isolate: pure-Dart decode/encode of a 12MP photo takes
/// several seconds.
({Uint8List bytes, img.Image image}) _enhanceSync(
  String imagePath, {
  Uint8List? bytes,
}) {
  final decoded =
      img.decodeImage(bytes ?? File(imagePath).readAsBytesSync());
  if (decoded == null) {
    throw AppException(
      StorageFailure('Unable to decode image at $imagePath'),
    );
  }

  final enhanced = img.adjustColor(
    _downscale(decoded),
    contrast: 1.12,
    brightness: 1.02,
  );
  return (
    bytes: Uint8List.fromList(img.encodeJpg(enhanced, quality: 92)),
    image: enhanced,
  );
}

double _laplacianVarianceOf(img.Image image) {
  final width = image.width;
  final height = image.height;
  if (width < 3 || height < 3) return 0;

  final gray = img.grayscale(image.clone()).convert(numChannels: 1);
  final px = gray.getBytes();

  var sum = 0.0;
  var sumSq = 0.0;
  var count = 0;
  for (var y = 1; y < height - 1; y++) {
    final row = y * width;
    for (var x = 1; x < width - 1; x++) {
      final i = row + x;
      final value = (px[i - width] + px[i + width] + px[i - 1] + px[i + 1] -
              4 * px[i])
          .toDouble();
      sum += value;
      sumSq += value * value;
      count++;
    }
  }
  if (count == 0) return 0;
  final mean = sum / count;
  return sumSq / count - mean * mean;
}
