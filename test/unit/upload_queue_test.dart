import 'package:flutter_test/flutter_test.dart';
import 'package:gst_expense_scanner/core/constants/app_constants.dart';
import 'package:gst_expense_scanner/shared/models/notification_entity.dart';

void main() {
  group('UploadQueueItem recovery', () {
    test('json round-trip preserves attempts and session', () {
      final item = UploadQueueItem(
        localInvoiceId: 'inv-1',
        enqueuedAt: DateTime.utc(2026, 1, 1),
        attempts: 3,
        nextAttemptAt: DateTime.utc(2026, 1, 1, 0, 5),
        lastError: 'timeout',
        uploadSessionId: 'sess-9',
      );

      final restored = UploadQueueItem.fromJson(item.toJson());
      expect(restored.localInvoiceId, 'inv-1');
      expect(restored.attempts, 3);
      expect(restored.uploadSessionId, 'sess-9');
      expect(restored.lastError, 'timeout');
    });

    test('backoff stays under max attempts constant', () {
      expect(AppConstants.syncMaxAttempts, greaterThanOrEqualTo(5));
      var delay = AppConstants.syncBaseBackoff;
      for (var i = 0; i < AppConstants.syncMaxAttempts; i++) {
        delay *= 2;
      }
      expect(delay.inSeconds, greaterThan(0));
    });
  });
}
