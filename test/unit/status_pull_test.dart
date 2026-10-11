import 'package:flutter_test/flutter_test.dart';
import 'package:gst_expense_scanner/features/sync/data/sync_engine.dart';
import 'package:gst_expense_scanner/features/uploads/data/datasources/invoice_local_datasource.dart';
import 'package:gst_expense_scanner/features/uploads/data/datasources/invoice_remote_datasource.dart';
import 'package:gst_expense_scanner/shared/models/invoice_entity.dart';

class _FakeLocal implements InvoiceLocalDataSource {
  final Map<String, InvoiceEntity> invoices = {};
  final Set<String> queue = {};

  @override
  Future<void> save(InvoiceEntity invoice) async =>
      invoices[invoice.localId] = invoice;

  @override
  Future<InvoiceEntity?> getById(String localId) async => invoices[localId];

  @override
  Future<List<InvoiceEntity>> list({SyncStatus? syncStatus}) async =>
      invoices.values
          .where((i) => syncStatus == null || i.syncStatus == syncStatus)
          .toList();

  @override
  Future<void> removeQueueItem(String localInvoiceId) async =>
      queue.remove(localInvoiceId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRemote implements InvoiceRemoteDataSource {
  _FakeRemote(this.items);

  List<Map<String, dynamic>> items;

  @override
  Future<List<Map<String, dynamic>>> fetchMine({int pageSize = 100}) async =>
      items;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

InvoiceEntity _invoice(String localId, {String? serverId}) => InvoiceEntity(
  localId: localId,
  serverId: serverId,
  companyId: 'c',
  employeeId: 'e',
  branchId: 'b',
  deviceId: 'd',
  createdAt: DateTime(2026, 10, 1),
  syncStatus: SyncStatus.uploaded,
  approvalStatus: ApprovalStatus.uploaded,
  ocrData: const InvoiceFieldData(),
  editedData: const InvoiceFieldData(invoiceNumber: 'INV-1'),
  ocrConfidence: 0.9,
  idempotencyKey: localId,
);

void main() {
  test('admin decisions from /invoices/mine reach local invoices', () async {
    final local = _FakeLocal()
      ..invoices['a'] = _invoice('a', serverId: 's-a')
      ..invoices['b'] = _invoice('b')
      ..invoices['c'] = _invoice('c', serverId: 's-c');
    final remote = _FakeRemote([
      {'id': 's-a', 'approvalStatus': 'approved', 'adminRemarks': null},
      {
        'id': 's-b',
        'localIdempotencyKey': 'b',
        'approvalStatus': 'returned',
        'adminRemarks': 'Photo the GST section',
      },
      {'id': 's-c', 'approvalStatus': 'pending'},
      {'id': 's-unknown', 'approvalStatus': 'approved'},
    ]);
    final engine = SyncEngine(localDataSource: local, remoteDataSource: remote);

    expect(await engine.pullStatuses(), 2);
    expect(engine.revision, 1);
    expect(local.invoices['a']!.approvalStatus, ApprovalStatus.approved);
    expect(local.invoices['b']!.approvalStatus, ApprovalStatus.returned);
    expect(local.invoices['b']!.serverId, 's-b');
    expect(local.invoices['b']!.adminRemarks, 'Photo the GST section');
    expect(local.invoices['c']!.approvalStatus, ApprovalStatus.uploaded);

    expect(await engine.pullStatuses(), 0, reason: 'no-op when unchanged');
    expect(engine.revision, 1);
  });

  test('a failing status pull never throws', () async {
    final engine = SyncEngine(
      localDataSource: _FakeLocal(),
      remoteDataSource: _ThrowingRemote(),
    );
    expect(await engine.pullStatuses(), 0);
  });
}

class _ThrowingRemote extends _FakeRemote {
  _ThrowingRemote() : super(const []);

  @override
  Future<List<Map<String, dynamic>>> fetchMine({int pageSize = 100}) =>
      Future.error(Exception('offline'));
}
