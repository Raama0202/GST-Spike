import 'dart:async';

import 'package:package_info_plus/package_info_plus.dart';

import 'package:gst_expense_scanner/core/errors/exceptions.dart';
import 'package:gst_expense_scanner/core/errors/failures.dart';
import 'package:gst_expense_scanner/core/services/push_service.dart';
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
    InvoiceImageStore? imageStore,
  }) : _remote = remote,
       _local = local,
       _database = database,
       _imageStore = imageStore ?? InvoiceImageStore();

  final AuthRemoteDataSource _remote;
  final AuthLocalDataSource _local;
  final LocalDatabase _database;
  final InvoiceImageStore _imageStore;

  @override
  Future<Result<OtpDelivery>> requestOtp(String mobile) async {
    try {
      return Success(await _remote.requestOtp(mobile));
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
  /// Restores the cached session without waiting on the network, so a cold
  /// server never holds up startup. Token validity is checked afterwards by
  /// [refreshSession]. The session is only cleared when the server rejects it.
  Future<Result<EmployeeEntity>> restoreSession() async {
    try {
      if (!await _local.hasValidSession()) {
        return const FailureResult(
          AuthFailure('Session expired. Please sign in again.'),
        );
      }

      var employee = await _local.readSession();
      if (employee == null) {
        // Sessions saved by early builds have tokens but no cached profile.
        final refreshed = await refreshSession();
        if (refreshed is FailureResult<bool>) {
          return FailureResult(refreshed.error);
        }
        employee = await _remote.fetchMe().timeout(const Duration(seconds: 20));
        final tokens = await _local.readTokens();
        if (tokens != null) {
          await _local.saveSession(tokens: tokens, employee: employee);
        }
      }

      await _database.openTenantBoxes(employee.companyId);
      unawaited(_registerDevice());
      return Success(employee);
    } catch (e) {
      final failure = ExceptionMapper.fromObject(e);
      if (failure is AuthFailure && failure.statusCode != null) {
        await _local.clearSession();
      }
      return FailureResult(failure);
    }
  }

  @override
  /// `Success(true)` when tokens were rotated, `Success(false)` when the
  /// refresh could not be attempted (offline, server down), and an
  /// [AuthFailure] when the server rejected the refresh token — the local
  /// session is cleared in that case and the user must sign in again.
  Future<Result<bool>> refreshSession() {
    // The startup check and a 401 retry can race; refresh tokens rotate, so a
    // second call with the same token would be rejected and sign the user out.
    return _refreshing ??= _refreshSession().whenComplete(() {
      _refreshing = null;
    });
  }

  Future<Result<bool>>? _refreshing;

  Future<Result<bool>> _refreshSession() async {
    try {
      final existing = await _local.readTokens();
      final refresh = existing?.refreshToken;
      if (refresh == null || refresh.isEmpty) {
        await _local.clearSession();
        return const FailureResult(_sessionExpired);
      }

      final tokens = await _remote.refreshToken(refresh);
      final employee = await _local.readSession() ?? await _remote.fetchMe();
      await _local.saveSession(tokens: tokens, employee: employee);
      return const Success(true);
    } catch (e) {
      final failure = ExceptionMapper.fromObject(e);
      if (failure is AuthFailure) {
        await _local.clearSession();
        return FailureResult(
          failure.isAccountBlocked ? failure : _sessionExpired,
        );
      }
      return const Success(false);
    }
  }

  static const _sessionExpired =
      AuthFailure('Your session has expired. Please sign in again.');

  @override
  Future<void> clearLocalSession() async {
    await PushService.instance.signOut();
    await _local.clearSession();
  }

  /// Best-effort: a failed registration must never block sign-in.
  Future<void> _registerDevice() async {
    try {
      final push = PushService.instance;
      await _sendDevice(await push.token());
      push.listenTokenRefresh(_sendDevice);
    } catch (_) {}
  }

  Future<void> _sendDevice(String? fcmToken) async {
    final info = await PackageInfo.fromPlatform();
    await _remote.registerDevice(
      deviceId: await _local.deviceId(),
      appVersion: info.version,
      fcmToken: fcmToken,
    );
  }

  @override
  Future<Result<void>> logout() async {
    try {
      // Server-side cleanup is best-effort and must run while the tokens
      // still exist; local state is always cleared.
      try {
        await _remote
            .unregisterDevice(await _local.deviceId())
            .timeout(const Duration(seconds: 6));
      } catch (_) {}
      try {
        final refresh = (await _local.readTokens())?.refreshToken;
        if (refresh != null) {
          await _remote.logout(refresh).timeout(const Duration(seconds: 6));
        }
      } catch (_) {}
      await PushService.instance.signOut();
      await _deleteTenantImages();
      await _local.clearSession();
      await _database.clearAllUserData();
      await _database.openTenantBoxes(null);
      return const Success(null);
    } catch (e) {
      return FailureResult(ExceptionMapper.fromObject(e));
    }
  }

  Future<void> _deleteTenantImages() async {
    try {
      final paths = <String?>[];
      for (final raw in _database.invoices.values) {
        if (raw is! Map) continue;
        paths
          ..add(raw['originalImagePath'] as String?)
          ..add(raw['compressedImagePath'] as String?)
          ..add(raw['thumbnailPath'] as String?);
      }
      await _imageStore.deleteForPaths(paths);
    } catch (_) {}
  }
}
