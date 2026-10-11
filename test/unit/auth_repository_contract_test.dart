import 'package:flutter_test/flutter_test.dart';
import 'package:gst_expense_scanner/core/utils/result.dart';
import 'package:gst_expense_scanner/features/auth/domain/repositories/auth_repository.dart';
import 'package:gst_expense_scanner/shared/models/employee_entity.dart';

class _FakeAuthRepository implements AuthRepository {
  bool requested = false;
  bool verified = false;

  @override
  Future<Result<void>> requestOtp(String mobile) async {
    requested = true;
    if (mobile.length != 10) {
      return const FailureResult('Invalid mobile');
    }
    return const Success(null);
  }

  @override
  Future<Result<EmployeeEntity>> verifyOtp({
    required String mobile,
    required String otp,
    required bool rememberLogin,
  }) async {
    verified = true;
    if (otp != '123456') {
      return const FailureResult('Invalid OTP');
    }
    return Success(
      EmployeeEntity(
        id: 'e1',
        name: 'Test User',
        mobile: mobile,
        companyId: 'c1',
        companyName: 'Test Co',
        branchId: 'b1',
        branchName: 'Main',
        employeeCode: 'EMP001',
      ),
    );
  }

  @override
  Future<Result<EmployeeEntity>> restoreSession() async =>
      const FailureResult('No session');

  @override
  Future<Result<bool>> refreshSession() async => const Success(false);

  @override
  Future<Result<void>> logout() async => const Success(null);
}

void main() {
  group('AuthRepository contract (fake)', () {
    late _FakeAuthRepository repo;

    setUp(() => repo = _FakeAuthRepository());

    test('requestOtp accepts 10-digit mobile', () async {
      final result = await repo.requestOtp('9876543210');
      expect(result.isSuccess, isTrue);
      expect(repo.requested, isTrue);
    });

    test('verifyOtp returns employee on correct OTP', () async {
      final result = await repo.verifyOtp(
        mobile: '9876543210',
        otp: '123456',
        rememberLogin: true,
      );
      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull?.companyId, 'c1');
    });

    test('verifyOtp fails on wrong OTP', () async {
      final result = await repo.verifyOtp(
        mobile: '9876543210',
        otp: '000000',
        rememberLogin: false,
      );
      expect(result.isFailure, isTrue);
    });
  });
}
