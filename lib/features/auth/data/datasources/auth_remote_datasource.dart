import 'package:flutter/foundation.dart';

import 'package:gst_expense_scanner/core/constants/app_constants.dart';
import 'package:gst_expense_scanner/core/errors/exceptions.dart';
import 'package:gst_expense_scanner/core/errors/failures.dart';
import 'package:gst_expense_scanner/core/network/api_client.dart';
import 'package:gst_expense_scanner/features/auth/domain/repositories/auth_repository.dart';
import 'package:gst_expense_scanner/shared/models/employee_entity.dart';

/// Remote authentication API backed by [ApiClient].
class AuthRemoteDataSource {
  AuthRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<OtpDelivery> requestOtp(String mobile) async {
    final response = await _apiClient.post<dynamic>(
      ApiEndpoints.requestOtp,
      data: {'mobile': mobile},
    );
    final data = response.data;
    final map = data is Map ? Map<String, dynamic>.from(data) : const {};
    final channel = map['channel'] == 'email' ? 'email' : 'sms';
    final destination = map['destination'] as String?;
    return OtpDelivery(
      channel: channel,
      destination: destination == null || destination.isEmpty
          ? mobile
          : destination,
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
    String? fcmToken,
  }) async {
    await _apiClient.post<void>(
      ApiEndpoints.deviceRegister,
      data: {
        'deviceId': deviceId,
        'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        'appVersion': appVersion,
        'fcmToken': fcmToken,
      },
    );
  }

  /// `DELETE /devices/{deviceId}` so pushes stop reaching a signed-out phone.
  Future<void> unregisterDevice(String deviceId) async {
    await _apiClient.delete<void>(ApiEndpoints.device(deviceId));
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
