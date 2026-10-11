import '../../../shared/models/invoice_entity.dart';

enum OcrExtractionSource { ai, onDevice }

/// OCR / AI extraction result including parsed invoice fields.
class OcrRunResult {
  const OcrRunResult({
    required this.data,
    required this.confidence,
    required this.rawText,
    this.source = OcrExtractionSource.onDevice,
  });

  final InvoiceFieldData data;
  final double confidence;
  final String rawText;
  final OcrExtractionSource source;
}
