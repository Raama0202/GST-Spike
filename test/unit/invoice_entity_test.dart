import 'package:flutter_test/flutter_test.dart';
import 'package:gst_expense_scanner/shared/models/invoice_entity.dart';

void main() {
  group('InvoiceEntity audit fields', () {
    test('keeps OCR and edited data independently', () {
      final ocr = const InvoiceFieldData(
        vendorName: 'OCR Vendor',
        netAmount: 100,
      );
      final edited = ocr.copyWith(vendorName: 'Corrected Vendor', netAmount: 110);

      final invoice = InvoiceEntity(
        localId: 'local-1',
        companyId: 'co-1',
        employeeId: 'emp-1',
        branchId: 'br-1',
        deviceId: 'dev-1',
        createdAt: DateTime.utc(2026, 3, 15),
        syncStatus: SyncStatus.pending,
        approvalStatus: ApprovalStatus.pending,
        ocrData: ocr,
        editedData: edited,
        ocrConfidence: 0.8,
        idempotencyKey: 'local-1',
      );

      expect(invoice.ocrData.vendorName, 'OCR Vendor');
      expect(invoice.editedData.vendorName, 'Corrected Vendor');
      expect(invoice.displayData.netAmount, 110);

      final roundTrip = InvoiceEntity.fromJson(invoice.toJson());
      expect(roundTrip.ocrData.vendorName, 'OCR Vendor');
      expect(roundTrip.editedData.vendorName, 'Corrected Vendor');
      expect(roundTrip.syncStatus, SyncStatus.pending);
    });
  });

  group('InvoiceFieldData', () {
    test('serializes and deserializes nullable amounts', () {
      const data = InvoiceFieldData(invoiceNumber: 'A-1');
      final json = data.toJson();
      final parsed = InvoiceFieldData.fromJson(json);
      expect(parsed.invoiceNumber, 'A-1');
      expect(parsed.gstin, isNull);
      expect(parsed.netAmount, isNull);
    });
  });
}
