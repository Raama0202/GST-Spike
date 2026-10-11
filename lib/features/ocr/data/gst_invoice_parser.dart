import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../shared/models/invoice_entity.dart';

/// Parsed OCR output with field-level confidence.
class GstParseResult {
  const GstParseResult({
    required this.data,
    required this.confidence,
    required this.rawText,
  });

  final InvoiceFieldData data;
  final double confidence;
  final String rawText;
}

/// Heuristic parser for Indian GST invoice OCR text.
class GstInvoiceParser {
  GstInvoiceParser();

  static final RegExp _gstinPattern = RegExp(
    r'\b([0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z])\b',
    caseSensitive: false,
  );

  static final RegExp _invoiceNumberPattern = RegExp(
    r'(?:invoice\s*(?:no\.?|number|#)|bill\s*no\.?)\s*[:\-]\s*([A-Za-z0-9][A-Za-z0-9\-\/]{0,31})',
    caseSensitive: false,
  );

  static final RegExp _shortInvPattern = RegExp(
    r'(?:^|[^\w])inv\.?\s*(?:no\.?|#)?\s*[:\-]\s*([A-Za-z0-9][A-Za-z0-9\-\/]{0,31})',
    caseSensitive: false,
  );

  GstParseResult parse(RecognizedText recognizedText) {
    final lines = _collectLines(recognizedText);
    final parsed = parseRawText(recognizedText.text, lines: lines);
    final confidence = _computeConfidence(
      data: parsed.data,
      recognizedText: recognizedText,
    );
    return GstParseResult(
      data: parsed.data,
      confidence: confidence,
      rawText: parsed.rawText,
    );
  }

  /// Text-only entry used by unit tests and fallback paths without ML Kit blocks.
  GstParseResult parseRawText(String rawText, {List<String>? lines}) {
    final normalized = rawText.replaceAll('\r', '\n');
    final resolvedLines = lines ??
        normalized
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();

    final gstin = _extractGstin(normalized);
    final invoiceNumber = _extractInvoiceNumber(normalized, resolvedLines);
    final invoiceDate = _extractInvoiceDate(normalized);
    final taxableValue = _extractLabeledAmount(
      normalized,
      const ['TAXABLE', 'TAXABLE VALUE', 'TAXABLE AMOUNT', 'ASSESSABLE'],
    );
    final cgst = _extractLabeledAmount(normalized, const ['CGST']);
    final sgst = _extractLabeledAmount(normalized, const ['SGST']);
    final discount =
        _extractLabeledAmount(normalized, const ['DISCOUNT', 'LESS DISCOUNT']);
    final netAmount = _extractNetAmount(normalized);
    final vendorName = _extractVendorName(resolvedLines, gstin);

    final data = InvoiceFieldData(
      vendorName: vendorName,
      gstin: gstin,
      invoiceNumber: invoiceNumber,
      invoiceDate: invoiceDate,
      taxableValue: taxableValue,
      cgst: cgst,
      sgst: sgst,
      discount: discount,
      netAmount: netAmount,
    );

    final fieldScore = _fieldScore(data);
    final confidence = rawText.trim().isEmpty
        ? 0.0
        : ((0.5 * 0.45) + (fieldScore * 0.55)).clamp(0.0, 1.0);

    return GstParseResult(
      data: data,
      confidence: confidence,
      rawText: rawText,
    );
  }

  double _fieldScore(InvoiceFieldData data) {
    var fieldScore = 0.0;
    if (data.gstin != null) fieldScore += 0.2;
    if (data.invoiceNumber != null) fieldScore += 0.15;
    if (data.invoiceDate != null) fieldScore += 0.15;
    if (data.netAmount != null) fieldScore += 0.2;
    if (data.taxableValue != null) fieldScore += 0.1;
    if (data.cgst != null || data.sgst != null) fieldScore += 0.1;
    if (data.vendorName != null) fieldScore += 0.1;
    return fieldScore;
  }

  List<String> _collectLines(RecognizedText recognizedText) {
    final lines = <String>[];
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final trimmed = line.text.trim();
        if (trimmed.isNotEmpty) lines.add(trimmed);
      }
    }
    if (lines.isEmpty && recognizedText.text.isNotEmpty) {
      lines.addAll(
        recognizedText.text
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty),
      );
    }
    return lines;
  }

  String? _extractGstin(String text) {
    final match = _gstinPattern.firstMatch(text.replaceAll(' ', ''));
    return match?.group(1)?.toUpperCase();
  }

  String? _extractInvoiceNumber(String text, List<String> lines) {
    final match = _invoiceNumberPattern.firstMatch(text) ??
        _shortInvPattern.firstMatch(text);
    if (match != null) {
      return match.group(1)?.trim();
    }

    for (final line in lines) {
      if (line.toLowerCase().contains('invoice') ||
          line.toLowerCase().contains('inv no')) {
        final parts = line.split(RegExp(r'[:#]'));
        if (parts.length > 1) {
          final candidate = parts.last.trim();
          if (candidate.isNotEmpty &&
              candidate.length <= 32 &&
              !candidate.toLowerCase().startsWith('invoice')) {
            return candidate;
          }
        }
      }
    }
    return null;
  }

  DateTime? _extractInvoiceDate(String text) {
    final patterns = [
      RegExp(r'\b(\d{2})[\/\-](\d{2})[\/\-](\d{4})\b'),
      RegExp(r'\b(\d{4})[\/\-](\d{2})[\/\-](\d{2})\b'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;

      if (pattern.pattern.contains(r'(\d{4})[\/\-](\d{2})')) {
        final year = int.tryParse(match.group(1)!);
        final month = int.tryParse(match.group(2)!);
        final day = int.tryParse(match.group(3)!);
        if (year != null && month != null && day != null) {
          return _safeDate(year, month, day);
        }
      } else {
        final day = int.tryParse(match.group(1)!);
        final month = int.tryParse(match.group(2)!);
        final year = int.tryParse(match.group(3)!);
        if (year != null && month != null && day != null) {
          return _safeDate(year, month, day);
        }
      }
    }

    final labeled = RegExp(
      r'(?:date|invoice\s*date|bill\s*date)\s*[:\-]?\s*(\d{2}[\/\-]\d{2}[\/\-]\d{4}|\d{4}[\/\-]\d{2}[\/\-]\d{2})',
      caseSensitive: false,
    ).firstMatch(text);
    if (labeled != null) {
      return _extractInvoiceDate(labeled.group(1)!);
    }

    return null;
  }

  DateTime? _safeDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day);
  }

  double? _extractLabeledAmount(String text, List<String> labels) {
    // Longer labels first so "TAXABLE VALUE" wins over "TAXABLE".
    final ordered = [...labels]
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final label in ordered) {
      final pattern = RegExp(
        '${RegExp.escape(label)}'
        r'(?:\s*@\s*[0-9]+(?:\.[0-9]+)?\s*%?)?'
        r'\s*[:\-]\s*(?:₹|rs\.?|inr)?\s*'
        r'([0-9]{1,3}(?:,[0-9]{3})+(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)',
        caseSensitive: false,
      );
      final match = pattern.firstMatch(text);
      if (match != null) {
        return _parseAmount(match.group(1));
      }
    }
    return null;
  }

  double? _extractNetAmount(String text) {
    final labels = [
      'GRAND TOTAL',
      'NET AMOUNT',
      'TOTAL AMOUNT',
      'AMOUNT PAYABLE',
      'INVOICE TOTAL',
      'TOTAL',
    ];

    double? best;
    for (final label in labels) {
      final value = _extractLabeledAmount(text, [label]);
      if (value != null && (best == null || value >= best)) {
        best = value;
      }
    }
    return best;
  }

  double? _parseAmount(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final cleaned = raw.replaceAll(',', '').trim();
    return double.tryParse(cleaned);
  }

  String? _extractVendorName(List<String> lines, String? gstin) {
    for (final line in lines.take(8)) {
      final lower = line.toLowerCase();
      if (lower.contains('tax invoice') ||
          lower.contains('invoice') && lower.length < 14 ||
          lower.startsWith('gstin') ||
          lower.startsWith('date')) {
        continue;
      }
      if (line.length >= 3 && line.length <= 80) {
        return line;
      }
    }

    if (gstin != null) {
      for (final line in lines) {
        if (line.toUpperCase().contains(gstin)) continue;
        if (RegExp(r'^[A-Za-z0-9 &.,\-]+$').hasMatch(line) &&
            line.length >= 3) {
          return line;
        }
      }
    }
    return null;
  }

  double _computeConfidence({
    required InvoiceFieldData data,
    required RecognizedText recognizedText,
  }) {
    final ocrConfidence = _averageOcrConfidence(recognizedText);
    final combined = (ocrConfidence * 0.45) + (_fieldScore(data) * 0.55);
    return combined.clamp(0.0, 1.0);
  }

  double _averageOcrConfidence(RecognizedText recognizedText) {
    final scores = <double>[];
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final confidence = line.confidence;
        if (confidence != null) scores.add(confidence);
        for (final element in line.elements) {
          final elementConfidence = element.confidence;
          if (elementConfidence != null) scores.add(elementConfidence);
        }
      }
    }

    if (scores.isEmpty) {
      return recognizedText.text.trim().isEmpty ? 0 : 0.5;
    }

    return scores.reduce((a, b) => a + b) / scores.length;
  }
}
