import 'package:dio/dio.dart' show ProgressCallback;
import 'package:flutter_test/flutter_test.dart';
import 'package:gst_expense_scanner/core/constants/app_constants.dart';
import 'package:gst_expense_scanner/core/errors/exceptions.dart';
import 'package:gst_expense_scanner/core/errors/failures.dart';
import 'package:gst_expense_scanner/core/network/api_client.dart';
import 'package:gst_expense_scanner/features/sync/data/sync_engine.dart';
import 'package:gst_expense_scanner/features/uploads/data/datasources/invoice_local_datasource.dart';
import 'package:gst_expense_scanner/features/uploads/data/datasources/invoice_remote_datasource.dart';
import 'package:gst_expense_scanner/shared/models/invoice_entity.dart';
import 'package:gst_expense_scanner/shared/models/notification_entity.dart';

class _Online extends ConnectivityService {
  @override
  Future<bool> get hasConnection async => true;
}

class _FakeLocal implements InvoiceLocalDataSource {
  final Map<String, InvoiceEntity> invoices = {};
  final Map<String, UploadQueueItem> queue = {};

  @override
  String get tenantId => 'c';

  @override
  Future<void> save(InvoiceEntity invoice) async =>
      invoices[invoice.localId] = invoice;

  @override
  Future<InvoiceEntity?> getById(String localId) async => invoices[localId];

  @override
  Future<List<InvoiceEntity>> list({SyncStatus? syncStatus}) async =>
      invoices.values.toList();

  @override
  Future<List<UploadQueueItem>> listQueueItems() async => queue.values.toList();

  @override
  Future<void> saveQueueItem(UploadQueueItem item) async =>
      queue[item.localInvoiceId] = item;

  @override
  Future<void> removeQueueItem(String localInvoiceId) async =>
      queue.remove(localInvoiceId);

  @override
  Future<DateTime?> lastStatusPullAt() async => null;

  @override
  Future<void> setLastStatusPullAt(DateTime at) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingRemote implements InvoiceRemoteDataSource {
  _FailingRemote(this.failure);

  final AppFailure failure;
  int uploads = 0;

  @override
  Future<String> uploadInvoice({
    required InvoiceEntity invoice,
    required String imagePath,
    ProgressCallback? onSendProgress,
  }) async {
    uploads++;
    throw AppException(failure);
  }

  @override
  Future<({List<Map<String, dynamic>> items, int total})> fetchMinePage({
    int page = 1,
    int pageSize = 100,
    DateTime? updatedSince,
  }) async => (items: const <Map<String, dynamic>>[], total: 0);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

InvoiceEntity _pending(String localId) => InvoiceEntity(
  localId: localId,
  companyId: 'c',
  employeeId: 'e',
  branchId: 'b',
  deviceId: 'd',
  createdAt: DateTime(2026, 10, 1),
  syncStatus: SyncStatus.pending,
  approvalStatus: ApprovalStatus.pending,
  ocrData: const InvoiceFieldData(),
  editedData: const InvoiceFieldData(invoiceNumber: 'INV-1'),
  ocrConfidence: 0.9,
  compressedImagePath: '/invoices/$localId/compressed.jpg',
  idempotencyKey: localId,
);

Future<(_FakeLocal, _FailingRemote)> _runWith(
  AppFailure failure, {
  int previousAttempts = 0,
}) async {
  final local = _FakeLocal()
    ..invoices['a'] = _pending('a')
    ..queue['a'] = UploadQueueItem(
      localInvoiceId: 'a',
      enqueuedAt: DateTime(2026, 10, 1),
      attempts: previousAttempts,
    );
  final remote = _FailingRemote(failure);
  final engine = SyncEngine(
    localDataSource: local,
    remoteDataSource: remote,
    connectivityService: _Online(),
  );
  await engine.syncNow();
  return (local, remote);
}

void main() {
  group('classifyUploadFailure', () {
    test('client errors are not retried', () {
      for (final status in [400, 413, 422]) {
        expect(
          classifyUploadFailure(ServerFailure('bad', statusCode: status)),
          UploadErrorKind.needsAttention,
          reason: '$status',
        );
      }
      expect(
        classifyUploadFailure(const ServerFailure('dup', statusCode: 409)),
        UploadErrorKind.duplicate,
      );
      expect(
        classifyUploadFailure(const ValidationFailure('bad')),
        UploadErrorKind.needsAttention,
      );
    });

    test('server and network errors are retried', () {
      expect(
        classifyUploadFailure(const ServerFailure('down', statusCode: 503)),
        UploadErrorKind.retryable,
      );
      expect(
        classifyUploadFailure(const ServerFailure('slow', statusCode: 429)),
        UploadErrorKind.retryable,
      );
      expect(
        classifyUploadFailure(const NetworkFailure()),
        UploadErrorKind.network,
      );
      expect(
        classifyUploadFailure(const AuthFailure('expired', statusCode: 401)),
        UploadErrorKind.paused,
      );
    });
  });

  test('backoff doubles and is capped', () {
    expect(uploadBackoff(1), AppConstants.syncBaseBackoff);
    expect(uploadBackoff(2), AppConstants.syncBaseBackoff * 2);
    expect(uploadBackoff(3), AppConstants.syncBaseBackoff * 4);
    expect(uploadBackoff(40), AppConstants.syncMaxBackoff);
  });

  test('a 409 marks the invoice as a duplicate and leaves the queue', () async {
    final (local, remote) = await _runWith(
      const ServerFailure('Duplicate invoice', statusCode: 409),
    );
    final invoice = local.invoices['a']!;
    expect(remote.uploads, 1);
    expect(invoice.syncStatus, SyncStatus.failed);
    expect(invoice.needsDuplicateOverride, isTrue);
    expect(invoice.lastUploadError, contains('Submit anyway'));
    expect(local.queue, isEmpty);
  });

  test('a 422 needs attention and shows the server message', () async {
    final (local, _) = await _runWith(
      const ServerFailure('Invoice date is in the future', statusCode: 422),
    );
    final invoice = local.invoices['a']!;
    expect(invoice.syncStatus, SyncStatus.failed);
    expect(invoice.uploadErrorCode, InvoiceEntity.errorRejected);
    expect(invoice.lastUploadError, 'Invoice date is in the future');
    expect(local.queue, isEmpty);
  });

  test('a 503 stays queued with a backoff time', () async {
    final before = DateTime.now();
    final (local, _) = await _runWith(
      const ServerFailure('Service unavailable', statusCode: 503),
    );
    final item = local.queue['a']!;
    expect(local.invoices['a']!.syncStatus, SyncStatus.pending);
    expect(item.attempts, 1);
    expect(
      item.nextAttemptAt!.isAfter(
        before.add(AppConstants.syncBaseBackoff - const Duration(seconds: 1)),
      ),
      isTrue,
    );
  });

  test('a 503 gives up after the attempt cap', () async {
    final (local, _) = await _runWith(
      const ServerFailure('Service unavailable', statusCode: 503),
      previousAttempts: AppConstants.syncMaxAttempts - 1,
    );
    expect(local.invoices['a']!.syncStatus, SyncStatus.failed);
    expect(local.queue, isEmpty);
  });

  test('network errors never exhaust the attempt budget', () async {
    final (local, _) = await _runWith(
      const NetworkFailure(),
      previousAttempts: AppConstants.syncMaxAttempts + 3,
    );
    expect(local.invoices['a']!.syncStatus, SyncStatus.pending);
    expect(local.queue['a'], isNotNull);
  });
}
