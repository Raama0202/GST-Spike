import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/storage.dart';

enum AdminRole { superAdmin, companyAdmin }

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
    final data = Map<String, dynamic>.from(response.data as Map);
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
      throw Exception(
        'Your subscription has expired. Sign in to the web dashboard '
        'to renew it, then use the app again.',
      );
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
  Future<AdminSession?> build() => ref.watch(authRepositoryProvider).restore();

  Future<void> login(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).login(email, password),
    );
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncData(null);
  }
}

final authProvider = AsyncNotifierProvider<AuthController, AdminSession?>(
  AuthController.new,
);
