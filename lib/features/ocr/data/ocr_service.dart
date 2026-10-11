import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../core/errors/exceptions.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/api_client.dart';
import 'ai_invoice_extract_remote_datasource.dart';
import 'gst_invoice_parser.dart';
import 'ocr_result.dart';

export 'ocr_result.dart';

/// Hybrid extractor: Gemini vision online, ML Kit + regex offline.
///
/// Template-varying Indian GST bills are poorly handled by regex alone. When
/// the API is reachable and GEMINI_API_KEY is configured server-side, the image
/// is sent for structured AI extraction. Otherwise (or on AI failure) the
/// previous on-device path still works so scanning is never blocked offline.
class OcrService {
  OcrService({
    TextRecognizer? recognizer,
    GstInvoiceParser? parser,
    AiInvoiceExtractRemoteDataSource? aiExtractor,
    ConnectivityService? connectivity,
  })  : _recognizer = recognizer ??
            TextRecognizer(script: TextRecognitionScript.latin),
        _parser = parser ?? GstInvoiceParser(),
        _aiExtractor = aiExtractor,
        _connectivity = connectivity ?? ConnectivityService(),
        _ownsRecognizer = recognizer == null;

  final TextRecognizer _recognizer;
  final GstInvoiceParser _parser;
  final AiInvoiceExtractRemoteDataSource? _aiExtractor;
  final ConnectivityService _connectivity;
  final bool _ownsRecognizer;
  bool _closed = false;

  Future<OcrRunResult> runOcr(String imagePath) async {
    if (_closed) {
      throw AppException(
        const OcrFailure('OCR recognizer has been closed.'),
      );
    }

    final file = File(imagePath);
    if (!await file.exists()) {
      throw AppException(
        OcrFailure('Image not found for OCR: $imagePath'),
      );
    }

    if (_aiExtractor != null && await _connectivity.hasConnection) {
      try {
        if (await _aiExtractor.isAvailable()) {
          return await _aiExtractor.extract(imagePath);
        }
      } catch (_) {
        // Fall through to on-device OCR — never block a scan on AI outage.
      }
    }

    return _runOnDevice(imagePath);
  }

  Future<OcrRunResult> _runOnDevice(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizedText = await _recognizer.processImage(inputImage);

      if (recognizedText.text.trim().isEmpty) {
        throw AppException(
          const OcrFailure('No text detected on the invoice image.'),
        );
      }

      final parsed = _parser.parse(recognizedText);
      return OcrRunResult(
        data: parsed.data,
        confidence: parsed.confidence,
        rawText: parsed.rawText,
        source: OcrExtractionSource.onDevice,
      );
    } on AppException {
      rethrow;
    } catch (error) {
      throw AppException(
        OcrFailure('OCR failed: $error'),
      );
    }
  }

  Future<void> close() async {
    if (_closed || !_ownsRecognizer) return;
    await _recognizer.close();
    _closed = true;
  }
}
