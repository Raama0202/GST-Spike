import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../shared/models/company_identity.dart';
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
///
/// A GST bill names two businesses: the supplier and the buyer (normally the
/// company scanning it). With a [CompanyIdentity], the company's own GSTINs
/// and names are never returned as the vendor.
class GstInvoiceParser {
  GstInvoiceParser();

  static final RegExp _gstinPattern = RegExp(
    r'([0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z])',
    caseSensitive: false,
  );

  /// Lines that open the recipient's block on a bill.
  static final RegExp _buyerLabel = RegExp(
    r'\b(bill(ed)?\s*to|buyer|customer|consignee|ship(ped)?\s*to|receiver|recipient|sold\s*to|party\s*(name|details))\b',
    caseSensitive: false,
  );

  /// Lines that open the supplier's block (ends a recipient block).
  static final RegExp _sellerLabel = RegExp(
    r'\b(seller|supplier|sold\s*by|details\s*of\s*supplier|issued\s*by)\b',
    caseSensitive: false,
  );

  /// Line items, totals and bank details end the party blocks.
  static final RegExp _bodyLabel = RegExp(
    r'\b(hsn|sac|qty|quantity|description|particulars|s\.?\s*no|sl\.?\s*no|total|bank)\b',
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

  GstParseResult parse(
    RecognizedText recognizedText, {
    CompanyIdentity? identity,
  }) {
    final lines = _collectLines(recognizedText);
    final parsed = parseRawText(
      recognizedText.text,
      lines: lines,
      identity: identity,
    );
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
  GstParseResult parseRawText(
    String rawText, {
    List<String>? lines,
    CompanyIdentity? identity,
  }) {
    final own = identity ?? CompanyIdentity.empty;
    final normalized = rawText.replaceAll('\r', '\n');
    final resolvedLines = lines ??
        normalized
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();

    final buyerLines = _buyerSectionLines(resolvedLines);
    final gstin = _extractVendorGstin(resolvedLines, buyerLines, own);
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
    final vendorName =
        _extractVendorName(resolvedLines, buyerLines, gstin, own);

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

  /// Indexes of lines inside a "Bill to / Buyer / Consignee" block. A block
  /// ends after its GSTIN line, at the next heading, or after a few lines.
  Set<int> _buyerSectionLines(List<String> lines) {
    const maxBlockLines = 5;
    final result = <int>{};
    var blockLines = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_sellerLabel.hasMatch(line) ||
          _bodyLabel.hasMatch(line) ||
          _headerNoise.hasMatch(line)) {
        blockLines = 0;
        continue;
      }
      if (_buyerLabel.hasMatch(line)) blockLines = maxBlockLines;
      if (blockLines == 0) continue;
      result.add(i);
      blockLines--;
      if (_gstinPattern.hasMatch(line.replaceAll(' ', ''))) blockLines = 0;
    }
    return result;
  }

  /// The supplier's GSTIN: never one of the company's own; a GSTIN outside
  /// the buyer block wins over one inside it; a GSTIN that only shares the
  /// company's PAN (its branch in another state) is the last resort.
  String? _extractVendorGstin(
    List<String> lines,
    Set<int> buyerLines,
    CompanyIdentity own,
  ) {
    final candidates = <({String gstin, int rank})>[];
    final seen = <String>{};
    for (var i = 0; i < lines.length; i++) {
      final compact = lines[i].replaceAll(' ', '');
      for (final match in _gstinPattern.allMatches(compact)) {
        final gstin = match.group(1)!.toUpperCase();
        if (!seen.add(gstin)) continue;
        final relation = own.gstinMatch(gstin);
        if (relation == GstinMatch.exact) continue;
        final rank = (relation == GstinMatch.samePan ? 2 : 0) +
            (buyerLines.contains(i) ? 1 : 0);
        candidates.add((gstin: gstin, rank: rank));
      }
    }
    if (candidates.isEmpty) return null;
    var best = candidates.first;
    for (final candidate in candidates.skip(1)) {
      if (candidate.rank < best.rank) best = candidate;
    }
    return best.gstin;
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
      'INVOICE VALUE',
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

  static final RegExp _headerNoise = RegExp(
    r'^(tax\s*invoice|invoice|bill\s*of\s*supply|cash\s*(memo|bill)|credit\s*bill|retail\s*invoice|estimate|original|duplicate|triplicate|for\s*recipient)\b',
    caseSensitive: false,
  );

  bool _isNameCandidate(String line, CompanyIdentity own) {
    final lower = line.toLowerCase();
    if (line.length < 3 || line.length > 80) return false;
    if (RegExp('[a-z]', caseSensitive: false).allMatches(line).length < 3) {
      return false;
    }
    if (_headerNoise.hasMatch(lower) && line.length < 30) return false;
    if (lower.contains('tax invoice') ||
        lower.contains('gstin') ||
        lower.startsWith('date') ||
        lower.startsWith('to ') ||
        lower.startsWith('to,') ||
        lower.startsWith('to:') ||
        RegExp(r'\b(ph|phone|mob|mobile|cell|email|e-mail|tel|irn|ack)\b|\b(pan|cin)\s*(no|:)')
            .hasMatch(lower) ||
        _buyerLabel.hasMatch(line) ||
        _sellerLabel.hasMatch(line) ||
        _bodyLabel.hasMatch(line)) {
      return false;
    }
    return !own.ownsName(line);
  }

  String? _extractVendorName(
    List<String> lines,
    Set<int> buyerLines,
    String? gstin,
    CompanyIdentity own,
  ) {
    // The supplier's name is printed in the bill header.
    for (var i = 0; i < lines.length && i < 8; i++) {
      if (buyerLines.contains(i)) continue;
      if (_isNameCandidate(lines[i], own)) return lines[i];
    }

    // Otherwise the name usually sits just above (or below) its GSTIN.
    if (gstin != null) {
      final at = lines.indexWhere(
        (line) => line.replaceAll(' ', '').toUpperCase().contains(gstin),
      );
      if (at >= 0) {
        for (final i in [at - 1, at - 2, at + 1]) {
          if (i < 0 || i >= lines.length) continue;
          if (_isNameCandidate(lines[i], own)) return lines[i];
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
