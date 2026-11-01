import 'package:equatable/equatable.dart';

sealed class AppFailure extends Equatable {
  const AppFailure(this.message, {this.code});

  final String message;
  final String? code;

  @override
  List<Object?> get props => [message, code];
}

class NetworkFailure extends AppFailure {
  const NetworkFailure([
    String message = 'No internet connection.',
    String? code,
  ]) : super(message, code: code);
}

class ServerFailure extends AppFailure {
  const ServerFailure(super.message, {super.code, this.statusCode});

  final int? statusCode;

  @override
  List<Object?> get props => [...super.props, statusCode];
}

class AuthFailure extends AppFailure {
  const AuthFailure(super.message, {super.code, this.statusCode});

  final int? statusCode;

  /// The whole company is blocked (suspended / subscription lapsed), as
  /// opposed to this user's session being invalid.
  bool get isAccountBlocked => AccountBlockCodes.contains(code);

  @override
  List<Object?> get props => [...super.props, statusCode];
}

/// Machine codes the API attaches to 403s when the company is blocked.
abstract final class AccountBlockCodes {
  static const suspended = 'COMPANY_SUSPENDED';
  static const subscriptionExpired = 'SUBSCRIPTION_EXPIRED';

  static bool contains(String? code) =>
      code == suspended || code == subscriptionExpired;

  static String messageFor(String? code) => switch (code) {
        suspended => 'Your company account is suspended. Please contact '
            'your administrator or support.',
        subscriptionExpired => "Your company's subscription has expired. "
            'Ask your administrator to renew it, then sign in again.',
        _ => 'Your company account is not active.',
      };
}

class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, {super.code});
}

class StorageFailure extends AppFailure {
  const StorageFailure(super.message, {super.code});
}

class OcrFailure extends AppFailure {
  const OcrFailure(super.message, {super.code});
}

class SyncFailure extends AppFailure {
  const SyncFailure(super.message, {super.code});
}

class CacheFailure extends AppFailure {
  const CacheFailure(super.message, {super.code});
}

class UnexpectedFailure extends AppFailure {
  const UnexpectedFailure([
    String message = 'Something went wrong. Please try again.',
    String? code,
  ]) : super(message, code: code);
}
