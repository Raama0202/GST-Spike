import 'package:flutter_test/flutter_test.dart';
import 'package:gst_expense_scanner/features/ocr/data/gst_invoice_parser.dart';
import 'package:gst_expense_scanner/shared/models/company_identity.dart';

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

  group('two companies on one bill', () {
    final buyer = CompanyIdentity(
      names: ['Surya Auto Builders'],
      gstins: ['37ABPFS2501J2ZY'],
    );

    test('buyer printed first is skipped for the vendor', () {
      const text = '''
Bill To: M/s. SURYA AUTO BUILDERS
GSTIN: 37ABPFS2501J2ZY
TAX INVOICE
SRI VIJAYALAKSHMI ENTERPRISES
GSTIN : 37AARFS2045J1ZS
Invoice No : G-25-26/11469
Date : 13-11-2025
NET AMOUNT : 62,495.00
''';
      final d = parser.parseRawText(text, identity: buyer).data;
      expect(d.gstin, '37AARFS2045J1ZS');
      expect(d.vendorName, contains('VIJAYALAKSHMI'));
    });

    test('company name in the header is skipped', () {
      const text = '''
SURYA AUTO BUILDERS PVT LTD
SRI VIJAYALAKSHMI ENTERPRISES
GSTIN 37AARFS2045J1ZS
37ABPFS2501J2ZY
Total : 1,180.00
''';
      final d = parser.parseRawText(text, identity: buyer).data;
      expect(d.gstin, '37AARFS2045J1ZS');
      expect(d.vendorName, isNot(contains('SURYA')));
    });

    test('without a profile the GSTIN outside the buyer block wins', () {
      const text = '''
Details of Receiver (Billed to)
M/s. SURYA AUTO BUILDERS
GSTIN: 37ABPFS2501J2ZY
Details of Supplier
SRI VIJAYALAKSHMI ENTERPRISES
GSTIN : 37AARFS2045J1ZS
HSN 320890 Qty 5
''';
      final d = parser.parseRawText(text).data;
      expect(d.gstin, '37AARFS2045J1ZS');
    });

    test('only the company on the bill leaves the GSTIN empty', () {
      const text = '''
Cash Memo
To: SURYA AUTO BUILDERS
GSTIN 37ABPFS2501J2ZY
Total 450
''';
      final d = parser.parseRawText(text, identity: buyer).data;
      expect(d.gstin, isNull);
    });
  });

  test('company identity matches names loosely and PAN across states', () {
    final identity = CompanyIdentity(
      names: ['Surya Auto Builders Private Limited'],
      gstins: ['37ABPFS2501J2ZY'],
    );
    expect(identity.ownsName('M/s. SURYA AUTO BUILDERS'), isTrue);
    expect(identity.ownsName('SURYA AUTO BUILDRS'), isTrue);
    expect(identity.ownsName('SRI VIJAYALAKSHMI ENTERPRISES'), isFalse);
    expect(identity.gstinMatch('37ABPFS2501J2ZY'), GstinMatch.exact);
    expect(identity.gstinMatch('29ABPFS2501J1ZA'), GstinMatch.samePan);
    expect(identity.gstinMatch('37AARFS2045J1ZS'), GstinMatch.none);
  });
}
