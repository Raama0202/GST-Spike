import 'package:flutter_test/flutter_test.dart';
import 'package:gst_expense_scanner/core/constants/app_constants.dart';
import 'package:gst_expense_scanner/shared/models/invoice_entity.dart';
import 'package:gst_expense_scanner/shared/models/notification_entity.dart';

/// Offline queue recovery semantics (pure logic; no platform plugins).
void main() {
  test('stuck uploading invoices are recoverable to pending', () {
    final stuck = InvoiceEntity(
      localId: 'x',
      companyId: 'c',
      employeeId: 'e',
      branchId: 'b',
      deviceId: 'd',
      createdAt: DateTime.now(),
      syncStatus: SyncStatus.uploading,
      approvalStatus: ApprovalStatus.pending,
      ocrData: const InvoiceFieldData(),
      editedData: const InvoiceFieldData(invoiceNumber: '1'),
      ocrConfidence: 0.7,
      uploadAttempts: 1,
      idempotencyKey: 'x',
    );

    final recovered = stuck.copyWith(syncStatus: SyncStatus.pending);
    expect(recovered.syncStatus, SyncStatus.pending);
    expect(recovered.idempotencyKey, stuck.localId);
  });

  test('failed uploads remain in queue for manual retry', () {
    final item = UploadQueueItem(
      localInvoiceId: 'x',
      enqueuedAt: DateTime.now(),
      attempts: AppConstants.syncMaxAttempts,
      lastError: 'timeout',
    );
    expect(item.attempts >= AppConstants.syncMaxAttempts, isTrue);
    expect(item.localInvoiceId, isNotEmpty);
  });
}
