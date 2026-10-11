import 'dart:io';

import 'package:dio/dio.dart';

import 'failures.dart';

class AppException implements Exception {
  AppException(this.failure);

  final AppFailure failure;

  @override
  String toString() => failure.message;
}

class ExceptionMapper {
  ExceptionMapper._();

  static AppFailure fromObject(Object error) {
    if (error is AppException) return error.failure;
    if (error is AppFailure) return error;
    if (error is DioException) return fromDio(error);
    return UnexpectedFailure(error.toString());
  }

  static AppFailure fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const NetworkFailure('Request timed out. Please try again.');
      case DioExceptionType.connectionError:
        return _connectionFailure(error);
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode;
        final data = error.response?.data;
        final extracted = _extractMessage(data);
        if (status == 429) {
          final wait = int.tryParse(
            error.response?.headers.value('retry-after') ?? '',
          );
          return ServerFailure(
            wait != null && wait > 0
                ? 'Too many requests. Please wait $wait seconds and try again.'
                : extracted ?? 'Too many requests. Please wait a moment.',
            statusCode: status,
            code: '429',
          );
        }
        if (status == 413) {
          return ServerFailure(
            extracted ?? 'That file is too large to upload.',
            statusCode: status,
            code: '413',
          );
        }
        if (status == 502 || status == 503 || status == 504) {
          return ServerFailure(
            extracted ??
                'The service is temporarily unavailable. Try again shortly.',
            statusCode: status,
            code: status.toString(),
          );
        }
        final requestId = data is Map ? data['requestId'] : null;
        final message = extracted == null
            ? 'Server error${status != null ? ' ($status)' : ''}.'
            : (requestId != null && (status ?? 0) >= 500
                ? '$extracted (ref $requestId)'
                : extracted);
        if (status == 401 || status == 403) {
          return AuthFailure(message, code: status?.toString());
        }
        return ServerFailure(message, statusCode: status, code: status?.toString());
      case DioExceptionType.cancel:
        return const UnexpectedFailure('Request cancelled.');
      case DioExceptionType.badCertificate:
        return const NetworkFailure('Secure connection failed.');
      case DioExceptionType.unknown:
        return _connectionFailure(error);
    }
  }

  /// Separates "device is offline" from "server address unreachable" so support
  /// can tell a Wi-Fi problem apart from a wrong/undeployed API endpoint.
  static AppFailure _connectionFailure(DioException error) {
    final cause = error.error;
    final description = cause is SocketException
        ? '${cause.osError?.message ?? ''} ${cause.message}'
        : error.message ?? '';
    final lower = description.toLowerCase();

    if (lower.contains('failed host lookup') ||
        lower.contains('no address associated') ||
        lower.contains('nodename nor servname')) {
      return const NetworkFailure(
        'Cannot reach the server address. Check your internet, '
        'or ask your administrator to verify the server setup.',
      );
    }
    if (lower.contains('connection refused') ||
        lower.contains('connection timed out') ||
        lower.contains('network is unreachable') ||
        lower.contains('software caused connection abort')) {
      return const NetworkFailure(
        'Server is not responding. Please try again shortly.',
      );
    }
    return const NetworkFailure();
  }

  static String? _extractMessage(Object? data) {
    if (data is Map) {
      final msg = data['message'] ?? data['error'] ?? data['detail'];
      if (msg is String && msg.isNotEmpty) return msg;
    }
    if (data is String && data.isNotEmpty) return data;
    return null;
  }
}
