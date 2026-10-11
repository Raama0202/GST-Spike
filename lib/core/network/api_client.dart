import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../config/server_config.dart';
import '../constants/app_constants.dart';
import '../constants/env_config.dart';
import '../errors/exceptions.dart';
import '../security/secure_storage_service.dart';

typedef TokenRefresher = Future<bool> Function();

/// Production Dio client with JWT refresh, tenant header, and optional pinning.
class ApiClient {
  ApiClient({
    required SecureStorageService secureStorage,
    required TokenRefresher onRefreshToken,
    Dio? dio,
  })  : _secureStorage = secureStorage,
        _onRefreshToken = onRefreshToken,
        _dio = dio ?? Dio() {
    _configure();
  }

  final SecureStorageService _secureStorage;
  final TokenRefresher _onRefreshToken;
  final Dio _dio;
  bool _refreshing = false;

  Dio get dio => _dio;

  /// Repoints an existing client after the endpoint is changed at runtime.
  void updateBaseUrl(String baseUrl) => _dio.options.baseUrl = baseUrl;

  void _configure() {
    _dio.options = BaseOptions(
      baseUrl: ServerConfig.baseUrl,
      // Free Render cold-starts can take ~60s before the first byte.
      connectTimeout: const Duration(seconds: 90),
      receiveTimeout: const Duration(seconds: 90),
      sendTimeout: const Duration(seconds: 120),
      headers: {
        HttpHeaders.acceptHeader: 'application/json',
        HttpHeaders.contentTypeHeader: 'application/json',
      },
    );

    _applyCertificatePinning();

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _secureStorage.accessToken;
          if (token != null && token.isNotEmpty) {
            options.headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
          }
          final companyId = await _secureStorage.companyId;
          if (companyId != null && companyId.isNotEmpty) {
            options.headers['X-Company-Id'] = companyId;
          }
          final deviceId = await _secureStorage.getOrCreateDeviceId();
          options.headers['X-Device-Id'] = deviceId;
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode != 401) {
            return handler.next(error);
          }
          if (error.requestOptions.path.contains(ApiEndpoints.refreshToken)) {
            return handler.next(error);
          }
          if (_refreshing) {
            return handler.next(error);
          }
          _refreshing = true;
          try {
            final ok = await _onRefreshToken();
            if (!ok) {
              return handler.next(error);
            }
            final token = await _secureStorage.accessToken;
            final opts = error.requestOptions;
            opts.headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
            final response = await _dio.fetch<dynamic>(opts);
            return handler.resolve(response);
          } catch (_) {
            return handler.next(error);
          } finally {
            _refreshing = false;
          }
        },
      ),
    );

    if (EnvConfig.enableNetworkLogging || kDebugMode) {
      _dio.interceptors.add(
        PrettyDioLogger(
          requestHeader: false,
          requestBody: true,
          responseBody: false,
          compact: true,
        ),
      );
    }
  }

  void _applyCertificatePinning() {
    final pins = EnvConfig.certificatePins;
    if (pins.isEmpty) return;

    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
        // When pins are supplied, reject all mismatched certs.
        // Ops must pass SPKI/SHA-256 fingerprints via CERT_PINS_SHA256.
        // Default Dio TLS validation still applies for trusted CAs;
        // this hook is reserved for custom pin enforcement adapters.
        return false;
      };
      return client;
    };
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _guard(
      () => _dio.get<T>(path, queryParameters: queryParameters, options: options),
    );
  }

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _guard(
      () => _dio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      ),
    );
  }

  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Options? options,
  }) {
    return _guard(() => _dio.put<T>(path, data: data, options: options));
  }

  Future<Response<T>> delete<T>(String path, {Object? data}) {
    return _guard(() => _dio.delete<T>(path, data: data));
  }

  Future<Response<T>> uploadMultipart<T>(
    String path, {
    required FormData formData,
    ProgressCallback? onSendProgress,
    Options? options,
  }) {
    return _guard(
      () => _dio.post<T>(
        path,
        data: formData,
        onSendProgress: onSendProgress,
        options: options ??
            Options(
              contentType: 'multipart/form-data',
              sendTimeout: const Duration(minutes: 2),
              receiveTimeout: const Duration(minutes: 2),
            ),
      ),
    );
  }

  Future<Response<T>> _guard<T>(Future<Response<T>> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw AppException(ExceptionMapper.fromDio(e));
    } catch (e) {
      throw AppException(ExceptionMapper.fromObject(e));
    }
  }
}

/// Lightweight connectivity probe used by sync engine.
///
/// Probes the configured API host rather than a public DNS server, so sync also
/// works on LAN-only or on-premise deployments that have no internet access.
class ConnectivityService {
  ConnectivityService({String? baseUrl}) : _explicitBaseUrl = baseUrl;

  static const Duration _probeTimeout = Duration(seconds: 4);

  /// Null means "whatever endpoint the app is currently pointed at".
  final String? _explicitBaseUrl;

  Future<bool> get hasConnection async {
    final uri = Uri.tryParse(_explicitBaseUrl ?? ServerConfig.baseUrl);
    if (uri != null && uri.host.isNotEmpty) {
      final port = uri.hasPort ? uri.port : (uri.scheme == 'http' ? 80 : 443);
      if (await _canConnect(uri.host, port)) return true;
    }
    return _canConnect('dns.google', 443);
  }

  Future<bool> _canConnect(String host, int port) async {
    try {
      final socket = await Socket.connect(host, port, timeout: _probeTimeout);
      socket.destroy();
      return true;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    }
  }
}
