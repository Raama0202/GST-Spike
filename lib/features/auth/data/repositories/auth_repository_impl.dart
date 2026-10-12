import 'dart:async';

import 'package:package_info_plus/package_info_plus.dart';

import 'package:gst_expense_scanner/core/errors/exceptions.dart';
import 'package:gst_expense_scanner/core/errors/failures.dart';
import 'package:gst_expense_scanner/core/storage/local_database.dart';
import 'package:gst_expense_scanner/core/utils/result.dart';
import 'package:gst_expense_scanner/features/auth/data/datasources/auth_local_datasource.dart';
import 'package:gst_expense_scanner/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:gst_expense_scanner/features/auth/domain/repositories/auth_repository.dart';
import 'package:gst_expense_scanner/shared/models/employee_entity.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required AuthRemoteDataSource remote,
    required AuthLocalDataSource local,
    required LocalDatabase database,
  }) : _remote = remote,
       _local = local,
       _database = database;

  final AuthRemoteDataSource _remote;
  final AuthLocalDataSource _local;
  final LocalDatabase _database;

  @override
  Future<Result<void>> requestOtp(String mobile) async {
    try {
      await _remote.requestOtp(mobile);
      return const Success(null);
    } catch (e) {
      return FailureResult(ExceptionMapper.fromObject(e));
    }
  }

  @override
  Future<Result<EmployeeEntity>> verifyOtp({
    required String mobile,
    required String otp,
    required bool rememberLogin,
  }) async {
    try {
      final session = await _remote.verifyOtp(mobile: mobile, otp: otp);
      await _local.setRememberLogin(rememberLogin);
      await _local.saveSession(
        tokens: session.tokens,
        employee: session.employee,
      );
      await _database.openTenantBoxes(session.employee.companyId);
      unawaited(_registerDevice());
      return Success(session.employee);
    } catch (e) {
      return FailureResult(ExceptionMapper.fromObject(e));
    }
  }

  @override
  Future<Result<EmployeeEntity>> restoreSession() async {
    try {
      if (!await _local.hasValidSession()) {
        return const FailureResult(
          AuthFailure('Session expired. Please sign in again.'),
        );
      }

      var employee = await _local.readSession();
      var tokens = await _local.readTokens();

      // A cached session opens offline and instantly; an expired access token
      // is refreshed by the ApiClient's 401 interceptor on the first call.
      if (employee == null || tokens == null) {
        await refreshSession();
        employee = await _local.readSession();
        tokens = await _local.readTokens();
      }

      if (employee == null || tokens == null) {
        employee = await _remote.fetchMe();
        tokens = await _local.readTokens();
        if (tokens != null) {
          await _local.saveSession(tokens: tokens, employee: employee);
        }
      }

      await _database.openTenantBoxes(employee.companyId);
      unawaited(_registerDevice());
      return Success(employee);
    } catch (e) {
      await _local.clearSession();
      return FailureResult(ExceptionMapper.fromObject(e));
    }
  }

  @override
  Future<Result<bool>> refreshSession() async {
    try {
      final existing = await _local.readTokens();
      final refresh = existing?.refreshToken;
      if (refresh == null || refresh.isEmpty) {
        return const Success(false);
      }

      final tokens = await _remote.refreshToken(refresh);
      final employee = await _local.readSession() ?? await _remote.fetchMe();
      await _local.saveSession(tokens: tokens, employee: employee);
      return const Success(true);
    } catch (_) {
      return const Success(false);
    }
  }

  /// Best-effort: a failed registration must never block sign-in.
  Future<void> _registerDevice() async {
    try {
      final info = await PackageInfo.fromPlatform();
      await _remote.registerDevice(
        deviceId: await _local.deviceId(),
        appVersion: info.version,
      );
    } catch (_) {}
  }

  @override
  Future<Result<void>> logout() async {
    try {
      try {
        final refresh = (await _local.readTokens())?.refreshToken;
        if (refresh != null) await _remote.logout(refresh);
      } catch (_) {
        // Best-effort server logout; always clear local state.
      }
      await _local.clearSession();
      await _database.clearAllUserData();
      await _database.openTenantBoxes(null);
      return const Success(null);
    } catch (e) {
      return FailureResult(ExceptionMapper.fromObject(e));
    }
  }
}
