import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gst_expense_scanner/core/errors/failures.dart';
import 'package:gst_expense_scanner/core/utils/result.dart';
import 'package:gst_expense_scanner/features/auth/domain/repositories/auth_repository.dart';
import 'package:gst_expense_scanner/features/company_config/domain/company_config_repository.dart';
import 'package:gst_expense_scanner/features/company_config/presentation/company_config_providers.dart';
import 'package:gst_expense_scanner/shared/models/employee_entity.dart';

/// Overridden during app bootstrap with a concrete [AuthRepository].
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  throw UnimplementedError('authRepositoryProvider must be overridden in DI.');
});

sealed class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

final class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

final class AuthAuthenticating extends AuthState {
  const AuthAuthenticating();
}

final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.employee);

  final EmployeeEntity employee;

  @override
  List<Object?> get props => [employee];
}

final class AuthErrorState extends AuthState {
  const AuthErrorState(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._ref) : super(const AuthUnauthenticated());

  final Ref _ref;

  AuthRepository get _repository => _ref.read(authRepositoryProvider);

  CompanyConfigRepository get _companyConfigRepository =>
      _ref.read(companyConfigRepositoryProvider);

  /// Returns where the code was sent, or null (with [AuthErrorState]) on failure.
  Future<OtpDelivery?> sendOtp(String mobile) async {
    state = const AuthAuthenticating();
    final result = await _repository.requestOtp(mobile);
    return result.fold(
      onSuccess: (delivery) {
        state = const AuthUnauthenticated();
        return delivery;
      },
      onFailure: (error) {
        state = AuthErrorState(_messageFrom(error));
        return null;
      },
    );
  }

  Future<bool> verifyOtp({
    required String mobile,
    required String otp,
    required bool rememberLogin,
  }) async {
    state = const AuthAuthenticating();
    final result = await _repository.verifyOtp(
      mobile: mobile,
      otp: otp,
      rememberLogin: rememberLogin,
    );

    return result.fold(
      onSuccess: (employee) {
        state = AuthAuthenticated(employee);
        _fetchCompanyConfig();
        return true;
      },
      onFailure: (error) {
        state = AuthErrorState(_messageFrom(error));
        return false;
      },
    );
  }

  /// Restores the cached session (no network), then validates the tokens in
  /// the background. Returns true when signed in.
  Future<bool> restore() async {
    state = const AuthAuthenticating();
    final result = await _repository.restoreSession();
    return result.fold(
      onSuccess: (employee) {
        state = AuthAuthenticated(employee);
        unawaited(_validateInBackground());
        return true;
      },
      onFailure: (error) {
        state = error is AuthFailure && error.isAccountBlocked
            ? AuthErrorState(error.message)
            : const AuthUnauthenticated();
        return false;
      },
    );
  }

  Future<void> _validateInBackground() async {
    final refreshed = await _repository.refreshSession();
    if (refreshed case FailureResult(:final error)) {
      if (error is AuthFailure && error.isAccountBlocked) {
        await accountBlocked(error.code);
      } else {
        await sessionExpired();
      }
      return;
    }
    await _fetchCompanyConfig();
  }

  /// The company is suspended or its subscription lapsed. Tokens are dropped
  /// but queued invoices are kept for when access is restored.
  Future<void> accountBlocked(String? code) async {
    if (state is! AuthAuthenticated) return;
    state = AuthErrorState(AccountBlockCodes.messageFor(code));
    _ref.read(companyConfigStateProvider.notifier).clear();
    await _repository.clearLocalSession();
  }

  Future<void> logout() async {
    state = const AuthAuthenticating();
    final result = await _repository.logout();
    result.fold(
      onSuccess: (_) {
        _ref.read(companyConfigStateProvider.notifier).clear();
        state = const AuthUnauthenticated();
      },
      onFailure: (error) => state = AuthErrorState(_messageFrom(error)),
    );
  }

  /// The server rejected the refresh token. Tokens are already cleared by the
  /// repository; queued invoices are kept so they upload after sign-in.
  Future<void> sessionExpired() async {
    if (state is! AuthAuthenticated) return;
    _ref.read(companyConfigStateProvider.notifier).clear();
    state = const AuthErrorState(
      'Your session has expired. Please sign in again.',
    );
  }

  void clearError() {
    if (state is AuthErrorState) {
      state = const AuthUnauthenticated();
    }
  }

  /// Re-reads company settings (GPS rule, OCR threshold, categories).
  Future<void> refreshCompanyConfig() async {
    if (state is! AuthAuthenticated) return;
    await _fetchCompanyConfig();
  }

  Future<void> _fetchCompanyConfig() async {
    final result = await _companyConfigRepository.fetchAndCache();
    result.fold(
      onSuccess: (config) {
        _ref.read(companyConfigStateProvider.notifier).setConfig(config);
      },
      onFailure: (_) {
        final cached = _companyConfigRepository.readCached();
        if (cached != null) {
          _ref.read(companyConfigStateProvider.notifier).setConfig(cached);
        }
      },
    );
  }

  String _messageFrom(Object error) {
    if (error is AppFailure) return error.message;
    return error.toString();
  }
}
