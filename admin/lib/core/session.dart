import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Company-level states in which the API refuses every admin request.
enum AccountBlock { subscriptionExpired, companySuspended }

/// Reads the machine code the API attaches to subscription/suspension 403s.
AccountBlock? accountBlockOf(Object error) {
  if (error is! DioException || error.response?.statusCode != 403) return null;
  final data = error.response?.data;
  final code = data is Map ? data['code']?.toString() : null;
  return switch (code) {
    'SUBSCRIPTION_EXPIRED' => AccountBlock.subscriptionExpired,
    'COMPANY_SUSPENDED' => AccountBlock.companySuspended,
    _ => null,
  };
}

class AccountBlockController extends Notifier<AccountBlock?> {
  @override
  AccountBlock? build() => null;
  void block(AccountBlock value) => state = value;
  void clear() => state = null;
}

final accountBlockProvider =
    NotifierProvider<AccountBlockController, AccountBlock?>(
      AccountBlockController.new,
    );

/// Bumped when the server rejects the refresh token. The auth controller
/// listens and drops the session so the router returns to sign-in.
class SessionExpiry extends Notifier<int> {
  @override
  int build() => 0;
  void expire() => state++;
}

final sessionExpiryProvider = NotifierProvider<SessionExpiry, int>(
  SessionExpiry.new,
);
