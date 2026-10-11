import 'package:gst_expense_scanner/core/utils/result.dart';
import 'package:gst_expense_scanner/shared/models/employee_entity.dart';

abstract class AuthRepository {
  Future<Result<void>> requestOtp(String mobile);

  Future<Result<EmployeeEntity>> verifyOtp({
    required String mobile,
    required String otp,
    required bool rememberLogin,
  });

  Future<Result<EmployeeEntity>> restoreSession();

  Future<Result<bool>> refreshSession();

  Future<Result<void>> logout();
}
