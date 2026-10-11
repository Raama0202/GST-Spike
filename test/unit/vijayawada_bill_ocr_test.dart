import 'package:flutter_test/flutter_test.dart';
import 'package:gst_expense_scanner/features/ocr/data/gst_invoice_parser.dart';

/// Realistic OCR dump from SRI VIJAYALAKSHMI ENTERPRISES tax invoice
/// (WhatsApp test bill — fields circled 1–6 by QA).
const vijayawadaBillOcr = '''
TAX INVOICE
GSTIN : 37AARFS2045J1ZS
SRI VIJAYALAKSHMI ENTERPRISES
#11-39-11, Kasturivari Street, Beside 1 Town Police Station, VIJAYAWADA-520001.
IRN: 924f28279f8b61ceaa4da688ed914aced75995496ed9467dc15a794e48987c87
Ack No. 112527639220990 Ack Date: 2025-11-13 18:43:00
Invoice No : G-25-26/11469
Date : 13-11-2025
Transportation : AUTO
Details of Receiver (Billed to)
M/s. SURYA AUTO BUILDERS
GSTIN: 37ABPFS2501J2ZY
Details of Consignee (Shipped to)
M/s. SURYA AUTO BUILDERS SITE AT GANNAVARAM
LUXOL SMOKE GREY 20LT HSN 320890 Qty 5 Taxable Value 18813.56 CGST 9% 1693.22 SGST 9% 1693.22 Amount 22200.00
Total Qty 60
Total Taxable Value 52961.86
Total CGST 4766.58
Total SGST 4766.58
Taxable Value : 52961.86
Total CGST : 4766.58
Total SGST : 4766.58
NET AMOUNT : 62,495.00
Rupees SIXTY TWO THOUSAND FOUR HUNDRED AND NINETY FIVE ONLY
''';

void main() {
  final parser = GstInvoiceParser();

  test('extracts circled fields from Vijayawada paint invoice', () {
    final result = parser.parseRawText(vijayawadaBillOcr);
    final d = result.data;

    expect(d.vendorName, contains('VIJAYALAKSHMI'));
    expect(d.gstin, '37AARFS2045J1ZS'); // seller, not buyer
    expect(d.invoiceNumber, 'G-25-26/11469');
    expect(d.invoiceDate, DateTime(2025, 11, 13));
    expect(d.taxableValue, closeTo(52961.86, 0.01));
    expect(d.cgst, closeTo(4766.58, 0.01));
    expect(d.sgst, closeTo(4766.58, 0.01));
    expect(d.netAmount, closeTo(62495.00, 0.01));
    expect(result.confidence, greaterThan(0.7));
  });
}
