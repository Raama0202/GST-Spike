import 'package:flutter_test/flutter_test.dart';
import 'package:gst_expense_scanner/features/ocr/data/gst_invoice_parser.dart';
import 'package:gst_expense_scanner/shared/models/invoice_entity.dart';

void main() {
  group('GstInvoiceParser', () {
    late GstInvoiceParser parser;

    setUp(() {
      parser = GstInvoiceParser();
    });

    test('extracts GSTIN, invoice number, date and tax amounts', () {
      const text = '''
ACME TRADERS PRIVATE LIMITED
GSTIN: 29ABCDE1234F1Z5
Tax Invoice
Invoice No: INV-2024-8891
Date: 15/03/2026
Taxable Value: 10000.00
CGST @9%: 900.00
SGST @9%: 900.00
Discount: 100.00
Grand Total: 11700.00
''';

      final result = parser.parseRawText(text);

      expect(result.data.gstin, '29ABCDE1234F1Z5');
      expect(result.data.invoiceNumber, contains('INV'));
      expect(result.data.invoiceDate, isNotNull);
      expect(result.data.taxableValue, 10000.0);
      expect(result.data.cgst, 900.0);
      expect(result.data.sgst, 900.0);
      expect(result.data.discount, 100.0);
      expect(result.data.netAmount, 11700.0);
      expect(result.confidence, greaterThan(0.5));
    });

    test('handles missing GSTIN without crashing', () {
      const text = '''
Local Kirana Store
Bill No: 42
Date: 01-01-2026
Total: 250.00
''';
      final result = parser.parseRawText(text);
      expect(result.data.gstin, isNull);
      expect(result.data.netAmount, 250.0);
    });

    test('empty text yields low confidence empty fields', () {
      final result = parser.parseRawText('');
      expect(result.data, isA<InvoiceFieldData>());
      expect(result.confidence, lessThan(0.3));
    });
  });
}
