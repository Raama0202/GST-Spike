import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';

/// Captures invoice images via ML Kit document scanner or gallery import.
class DocumentScannerService {
  DocumentScannerService({
    ImagePicker? imagePicker,
    DocumentScannerOptions? scannerOptions,
  })  : _imagePicker = imagePicker ?? ImagePicker(),
        _scannerOptions = scannerOptions ??
            DocumentScannerOptions(
              documentFormat: DocumentFormat.jpeg,
              pageLimit: 1,
              mode: ScannerMode.full,
              isGalleryImport: true,
            );

  final ImagePicker _imagePicker;
  final DocumentScannerOptions _scannerOptions;
  DocumentScanner? _scanner;

  DocumentScanner get _documentScanner {
    _scanner ??= DocumentScanner(options: _scannerOptions);
    return _scanner!;
  }

  /// Opens the native document scanner UI. Returns null when cancelled.
  Future<String?> scanDocument() async {
    try {
      final result = await _documentScanner.scanDocument();
      if (result.images.isEmpty) return null;
      return result.images.first;
    } on PlatformException catch (e) {
      if (_isCancellation(e)) return null;
      rethrow;
    }
  }

  /// Picks a single image from the device gallery.
  Future<String?> pickFromGallery() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );
    if (picked == null) return null;
    return picked.path;
  }

  /// Validates that a scanned path exists on disk.
  Future<bool> validateImagePath(String? path) async {
    if (path == null || path.isEmpty) return false;
    return File(path).exists();
  }

  Future<void> dispose() async {
    await _scanner?.close();
    _scanner = null;
  }

  bool _isCancellation(PlatformException error) {
    final code = error.code.toLowerCase();
    final message = (error.message ?? '').toLowerCase();
    return code.contains('cancel') ||
        message.contains('cancel') ||
        message.contains('user') && message.contains('back');
  }
}
