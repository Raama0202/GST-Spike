import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gst_expense_scanner/core/errors/exceptions.dart';
import 'package:gst_expense_scanner/core/errors/failures.dart';
import 'package:gst_expense_scanner/features/uploads/data/datasources/invoice_local_datasource.dart';
import 'package:gst_expense_scanner/features/uploads/data/datasources/invoice_remote_datasource.dart';
import 'package:gst_expense_scanner/features/uploads/data/repositories/invoice_repository_impl.dart';
import 'package:gst_expense_scanner/features/uploads/domain/repositories/invoice_repository.dart';
import 'package:gst_expense_scanner/shared/models/invoice_entity.dart';

class _EmptyLocal implements InvoiceLocalDataSource {
  @override
  Future<List<InvoiceEntity>> findLocalDuplicates({
    String? gstin,
    String? invoiceNumber,
    DateTime? invoiceDate,
    String? excludeLocalId,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Remote implements InvoiceRemoteDataSource {
  _Remote(this._check);

  final Future<DuplicateCheckResult> Function() _check;

  @override
  Future<DuplicateCheckResult> checkDuplicate(
    InvoiceFieldData data, {
    Duration? timeout,
  }) => _check();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _bill = InvoiceFieldData(
  gstin: '37ABCDE1234F1Z5',
  invoiceNumber: 'INV-77',
  invoiceDate: DateTime(2026, 10, 1),
);

InvoiceRepositoryImpl _repo(
  Future<DuplicateCheckResult> Function() check, {
  Duration timeout = const Duration(seconds: 8),
}) => InvoiceRepositoryImpl(
  localDataSource: _EmptyLocal(),
  remoteDataSource: _Remote(check),
  duplicateCheckTimeout: timeout,
);

void main() {
  test('offline: the check is unknown and saving can continue', () async {
    final result = await _repo(
      () => Future.error(AppException(const NetworkFailure())),
    ).checkDuplicate(_bill);
    expect(result.isDuplicate, isFalse);
    expect(result.checked, isFalse);
  });

  test('a hanging server is abandoned after the timeout', () async {
    final never = Completer<DuplicateCheckResult>();
    final stopwatch = Stopwatch()..start();
    final result = await _repo(
      () => never.future,
      timeout: const Duration(milliseconds: 50),
    ).checkDuplicate(_bill);
    expect(result.checked, isFalse);
    expect(result.isDuplicate, isFalse);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('server errors and expired sessions do not block saving', () async {
    for (final failure in [
      const ServerFailure('Bad gateway', statusCode: 502),
      const AuthFailure('Session expired', statusCode: 401),
    ]) {
      final result = await _repo(
        () => Future.error(AppException(failure)),
      ).checkDuplicate(_bill);
      expect(result.checked, isFalse, reason: failure.message);
    }
  });

  test('a real duplicate from the server is still reported', () async {
    final result = await _repo(
      () async => const DuplicateCheckResult(
        isDuplicate: true,
        existingServerId: 's-1',
        source: 'server',
      ),
    ).checkDuplicate(_bill);
    expect(result.isDuplicate, isTrue);
    expect(result.checked, isTrue);
  });
}
