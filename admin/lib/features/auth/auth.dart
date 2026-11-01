import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/session.dart';
import '../../core/storage.dart';

enum AdminRole { superAdmin, companyAdmin }

class RegistrationOptions {
  const RegistrationOptions({
    required this.enabled,
    required this.available,
    required this.verificationRequired,
    required this.trialDays,
    required this.trialSeats,
    this.passwordReset = true,
  });

  factory RegistrationOptions.fromJson(Map<String, dynamic> json) =>
      RegistrationOptions(
        enabled: json['enabled'] != false,
        available: json['available'] != false,
        verificationRequired: json['verificationRequired'] != false,
        trialDays: (json['trialDays'] as num?)?.toInt() ?? 14,
        trialSeats: (json['trialSeats'] as num?)?.toInt() ?? 5,
        passwordReset: json['passwordReset'] != false,
      );

  /// False when the server can't send email, so reset codes can't arrive.
  final bool passwordReset;
  final bool enabled;
  final bool available;
  final bool verificationRequired;
  final int trialDays;
  final int trialSeats;
}

class FirmRegistration {
  const FirmRegistration({
    required this.companyName,
    required this.adminName,
    required this.adminEmail,
    required this.adminPassword,
    this.legalName,
    this.gstin,
    this.mobile,
  });

  final String companyName;
  final String adminName;
  final String adminEmail;
  final String adminPassword;
  final String? legalName;
  final String? gstin;
  final String? mobile;

  static String? _optional(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  Map<String, dynamic> toJson() => {
    'companyName': companyName.trim(),
    'legalName': _optional(legalName),
    'gstin': _optional(gstin?.toUpperCase().replaceAll(' ', '')),
    'adminName': adminName.trim(),
    'adminEmail': adminEmail.trim().toLowerCase(),
    'mobile': _optional(mobile),
    'adminPassword': adminPassword,
  };
}

class AdminSession extends Equatable {
  const AdminSession({
    required this.token,
    required this.role,
    this.companyId,
    this.name,
    this.email,
  });
  final String token;
  final AdminRole role;
  final String? companyId;
  final String? name;
  final String? email;
  @override
  List<Object?> get props => [token, role, companyId, name, email];
}

class AuthRepository {
  AuthRepository(this._dio, this._store);
  final Dio _dio;
  final SecureStore _store;

  Future<AdminSession?> restore() async {
    try {
      final token = await _store.token;
      final role = await _store.role;
      if (token == null || role == null) return null;
      if (_parseRole(role) == AdminRole.superAdmin) {
        await _store.clear();
        return null;
      }
      return AdminSession(
        token: token,
        role: _parseRole(role),
        companyId: await _store.companyId,
        name: await _store.displayName,
      );
    } catch (_) {
      // Unreadable stored session (e.g. web encryption key mismatch).
      await _store.clear().catchError((_) {});
      return null;
    }
  }

  Future<AdminSession> login(String email, String password) async {
    final response = await _dio.post(
      ApiPaths.login,
      data: {'email': email.trim(), 'password': password},
    );
    return _adopt(Map<String, dynamic>.from(response.data as Map), email);
  }

  /// Public sign-up settings, or null when the server can't be reached.
  Future<RegistrationOptions?> registrationOptions() async {
    try {
      final response = await _dio.get(ApiPaths.registerOptions);
      return RegistrationOptions.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } catch (_) {
      return null;
    }
  }

  /// Step 1 of firm sign-up. Returns where the code was emailed, or signs the
  /// admin straight in (returns a session) when email verification is off.
  Future<({String? destination, AdminSession? session})> register(
    FirmRegistration form,
  ) async {
    final response = await _dio.post(ApiPaths.register, data: form.toJson());
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['verificationRequired'] == false) {
      return (destination: null, session: await _adopt(data, form.adminEmail));
    }
    return (destination: data['destination']?.toString(), session: null);
  }

  Future<String?> resendRegistrationCode(String email) async {
    final response = await _dio.post(
      ApiPaths.registerResend,
      data: {'email': email.trim().toLowerCase()},
    );
    return (response.data as Map?)?['destination']?.toString();
  }

  /// Step 2: the emailed code creates the firm and signs its admin in. The
  /// server requires the same password as step 1.
  Future<AdminSession> verifyRegistration(
    String email,
    String code,
    String password,
  ) async {
    final response = await _dio.post(
      ApiPaths.registerVerify,
      data: {
        'email': email.trim().toLowerCase(),
        'code': code.trim(),
        'password': password,
      },
    );
    return _adopt(Map<String, dynamic>.from(response.data as Map), email);
  }

  /// Emails a reset code. Returns the masked destination.
  Future<String?> forgotPassword(String email) async {
    final response = await _dio.post(
      ApiPaths.passwordForgot,
      data: {'email': email.trim().toLowerCase()},
    );
    return (response.data as Map?)?['destination']?.toString();
  }

  Future<void> resetPassword(String email, String code, String newPassword) =>
      _dio.post(
        ApiPaths.passwordReset,
        data: {
          'email': email.trim().toLowerCase(),
          'code': code.trim(),
          'newPassword': newPassword,
        },
      );

  /// Other sessions are signed out; this device keeps working with the new
  /// tokens the server returns.
  Future<void> changePassword(String current, String next) async {
    final response = await _dio.post(
      ApiPaths.changePassword,
      data: {'currentPassword': current, 'newPassword': next},
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    final token = data['accessToken']?.toString();
    if (token != null && token.isNotEmpty) {
      await _store.saveTokens(token, data['refreshToken']?.toString());
    }
  }

  /// Permanently deletes the company and all of its data.
  Future<void> deleteCompany({
    required String password,
    required String confirmName,
  }) async {
    await _dio.post(
      ApiPaths.companyDelete,
      data: {'password': password, 'confirmName': confirmName.trim()},
    );
    await _store.clear();
  }

  Future<AdminSession> _adopt(Map<String, dynamic> data, String email) async {
    final user = data['admin'] is Map
        ? Map<String, dynamic>.from(data['admin'] as Map)
        : data['user'] is Map
        ? Map<String, dynamic>.from(data['user'] as Map)
        : data;
    final token = (data['accessToken'] ?? data['access_token'] ?? data['token'])
        ?.toString();
    if (token == null || token.isEmpty) {
      throw Exception('Login response did not include an access token.');
    }
    final roleText = (user['role'] ?? data['role'] ?? 'company_admin')
        .toString();
    if (_parseRole(roleText) == AdminRole.superAdmin) {
      throw Exception(
        'Super admin accounts use the web dashboard. '
        'This app is for company administrators.',
      );
    }
    if (data['billingRequired'] == true) {
      throw const AccountBlockedException(AccountBlock.subscriptionExpired);
    }
    final session = AdminSession(
      token: token,
      role: _parseRole(roleText),
      companyId: (user['companyId'] ?? user['company_id'] ?? data['companyId'])
          ?.toString(),
      name: (user['name'] ?? user['displayName'])?.toString(),
      email: (user['email'] ?? email).toString(),
    );
    await _store.saveSession(
      token: token,
      refreshToken: (data['refreshToken'] ?? data['refresh_token'])?.toString(),
      role: session.role.name,
      companyId: session.companyId,
      displayName: session.name,
    );
    return session;
  }

  AdminRole _parseRole(String value) =>
      value.toLowerCase().replaceAll('-', '_').contains('super')
      ? AdminRole.superAdmin
      : AdminRole.companyAdmin;

  Future<void> logout() async {
    final refreshToken = await _store.refreshToken;
    if (refreshToken != null) {
      try {
        await _dio
            .post(ApiPaths.logout, data: {'refreshToken': refreshToken})
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    await _store.clear();
  }
}

final authRepositoryProvider = Provider(
  (ref) =>
      AuthRepository(ref.watch(dioProvider), ref.watch(secureStoreProvider)),
);

class AuthController extends AsyncNotifier<AdminSession?> {
  @override
  Future<AdminSession?> build() {
    ref.listen(sessionExpiryProvider, (_, _) {
      state = const AsyncData(null);
    });
    return ref.watch(authRepositoryProvider).restore();
  }

  /// Throws on failure so the sign-in form can show the error in place.
  Future<void> login(String email, String password) async {
    try {
      final session = await ref
          .read(authRepositoryProvider)
          .login(email, password);
      state = AsyncData(session);
    } on AccountBlockedException catch (blocked) {
      ref.read(accountBlockProvider.notifier).block(blocked.block);
    }
  }

  /// Use a session obtained outside [login] (e.g. firm sign-up).
  void signedIn(AdminSession session) => state = AsyncData(session);

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    ref.read(accountBlockProvider.notifier).clear();
    state = const AsyncData(null);
  }

  /// After the company was deleted server-side; tokens are already gone.
  void signedOutLocally() {
    ref.read(accountBlockProvider.notifier).clear();
    state = const AsyncData(null);
  }
}

class AccountBlockedException implements Exception {
  const AccountBlockedException(this.block);
  final AccountBlock block;
}

final authProvider = AsyncNotifierProvider<AuthController, AdminSession?>(
  AuthController.new,
);
