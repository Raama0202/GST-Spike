import 'package:gst_expense_scanner/core/utils/result.dart';
import 'package:gst_expense_scanner/shared/models/employee_entity.dart';

/// Where the server sent the login code.
class OtpDelivery {
  const OtpDelivery({required this.channel, required this.destination});

  /// `email` or `sms`.
  final String channel;

  /// Masked address, e.g. `ra***@gmail.com` or `98******10`.
  final String destination;

  bool get isEmail => channel == 'email';
}

abstract class AuthRepository {
  Future<Result<OtpDelivery>> requestOtp(String mobile);

  Future<Result<EmployeeEntity>> verifyOtp({
    required String mobile,
    required String otp,
    required bool rememberLogin,
  });

  /// Local only: restores the cached session without a network round trip.
  Future<Result<EmployeeEntity>> restoreSession();

  Future<Result<bool>> refreshSession();

  /// Drops tokens but keeps queued invoices, so they upload after the user
  /// signs in again (session expired, company blocked).
  Future<void> clearLocalSession();

  Future<Result<void>> logout();
}
