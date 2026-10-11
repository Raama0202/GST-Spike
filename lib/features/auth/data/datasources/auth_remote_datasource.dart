import 'package:gst_expense_scanner/core/constants/app_constants.dart';
import 'package:gst_expense_scanner/core/errors/exceptions.dart';
import 'package:gst_expense_scanner/core/errors/failures.dart';
import 'package:gst_expense_scanner/core/network/api_client.dart';
import 'package:gst_expense_scanner/shared/models/employee_entity.dart';

/// Remote authentication API backed by [ApiClient].
class AuthRemoteDataSource {
  AuthRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<void> requestOtp(String mobile) async {
    await _apiClient.post<void>(
      ApiEndpoints.requestOtp,
      data: {'mobile': mobile},
    );
  }

  Future<AuthSession> verifyOtp({
    required String mobile,
    required String otp,
  }) async {
    final response = await _apiClient.post<dynamic>(
      ApiEndpoints.verifyOtp,
      data: {'mobile': mobile, 'otp': otp},
    );
    return _parseAuthSession(response.data);
  }

  Future<AuthTokens> refreshToken(String refreshToken) async {
    final response = await _apiClient.post<dynamic>(
      ApiEndpoints.refreshToken,
      data: {'refreshToken': refreshToken},
    );
    return AuthTokens.fromJson(_asMap(response.data));
  }

  Future<void> logout(String refreshToken) async {
    await _apiClient.post<void>(
      ApiEndpoints.logout,
      data: {'refreshToken': refreshToken},
    );
  }

  Future<void> registerDevice({
    required String deviceId,
    required String appVersion,
  }) async {
    await _apiClient.post<void>(
      ApiEndpoints.deviceRegister,
      data: {
        'deviceId': deviceId,
        'platform': 'android',
        'appVersion': appVersion,
        'fcmToken': null,
      },
    );
  }

  Future<EmployeeEntity> fetchMe() async {
    final response = await _apiClient.get<dynamic>(ApiEndpoints.me);
    return EmployeeEntity.fromJson(_asMap(response.data));
  }

  AuthSession _parseAuthSession(dynamic data) {
    final map = _asMap(data);
    final tokens = AuthTokens.fromJson(map);
    final employeePayload = map['employee'] ?? map['profile'] ?? map['user'];
    final employeeMap = employeePayload is Map
        ? Map<String, dynamic>.from(employeePayload)
        : map;
    return AuthSession(
      tokens: tokens,
      employee: EmployeeEntity.fromJson(employeeMap),
    );
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw AppException(
      const UnexpectedFailure(
        'Unexpected response from authentication service.',
      ),
    );
  }
}
