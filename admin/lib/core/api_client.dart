import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'constants.dart';
import 'server_config.dart';
import 'storage.dart';

final secureStoreProvider = Provider(
  (ref) => SecureStore(
    const FlutterSecureStorage(
      aOptions: AndroidOptions(),
      webOptions: WebOptions(
        dbName: 'gst_expense_admin',
        publicKey: 'gst-expense-admin-session',
      ),
    ),
  ),
);

/// Free Render services can take 30–60s to wake after idle.
final dioProvider = Provider<Dio>((ref) {
  final store = ref.watch(secureStoreProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: ServerConfig.baseUrl,
      connectTimeout: const Duration(seconds: 90),
      receiveTimeout: const Duration(seconds: 90),
      sendTimeout: const Duration(seconds: 120),
      headers: const {'Accept': 'application/json'},
    ),
  );
  Future<String?>? refreshing;

  Future<String?> refresh() async {
    final refreshToken = await store.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return null;
    try {
      final response = await Dio(
        BaseOptions(
          baseUrl: dio.options.baseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      ).post(ApiPaths.refresh, data: {'refreshToken': refreshToken});
      final data = Map<String, dynamic>.from(response.data as Map);
      final token = data['accessToken']?.toString();
      if (token == null || token.isEmpty) return null;
      await store.saveTokens(token, data['refreshToken']?.toString());
      return token;
    } catch (_) {
      return null;
    }
  }

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await store.token;
        final companyId = await store.companyId;
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        if (companyId != null) options.headers['X-Company-Id'] = companyId;
        handler.next(options);
      },
      onError: (error, handler) async {
        final options = error.requestOptions;
        if (error.response?.statusCode != 401 ||
            options.path == ApiPaths.login ||
            options.extra['retried'] == true) {
          return handler.next(error);
        }
        // Concurrent 401s share one refresh call.
        refreshing ??= refresh().whenComplete(() => refreshing = null);
        final token = await refreshing;
        if (token == null) return handler.next(error);
        options.headers['Authorization'] = 'Bearer $token';
        options.extra['retried'] = true;
        try {
          handler.resolve(await dio.fetch<dynamic>(options));
        } on DioException catch (retryError) {
          handler.next(retryError);
        }
      },
    ),
  );
  return dio;
});

void updateAdminBaseUrl(WidgetRef ref, String baseUrl) {
  ref.read(dioProvider).options.baseUrl = baseUrl;
}

String apiError(Object error) {
  if (error is DioException) {
    final response = error.response;
    final data = response?.data;
    final message = data is Map && data['message'] != null
        ? data['message'].toString()
        : null;
    switch (response?.statusCode) {
      case 429:
        final wait = int.tryParse(response?.headers.value('retry-after') ?? '');
        return wait != null && wait > 0
            ? 'Too many requests. Please wait $wait seconds and try again.'
            : (message ?? 'Too many requests. Please wait a moment.');
      case 413:
        return message ?? 'That file is too large to upload.';
      case 502:
      case 503:
      case 504:
        return message ??
            'The service is temporarily unavailable. Try again shortly.';
    }
    if (message != null) {
      final requestId = data is Map ? data['requestId'] : null;
      return requestId != null && (response?.statusCode ?? 0) >= 500
          ? '$message (ref $requestId)'
          : message;
    }
    switch (error.type) {
      case DioExceptionType.connectionError:
        return 'Cannot reach the server. Check the API URL and connection.';
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'The server took too long to respond. Please try again.';
      default:
        return error.message ?? 'Request failed';
    }
  }
  return error.toString().replaceFirst('Exception: ', '');
}

List<Map<String, dynamic>> itemList(dynamic data) {
  final raw = data is Map
      ? (data['items'] ?? data['data'] ?? data['results'])
      : data;
  if (raw is! List) return const [];
  return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

/// Server-side total for paginated responses, falling back to the page length.
int itemTotal(dynamic data) {
  if (data is Map && data['total'] is num)
    return (data['total'] as num).toInt();
  return itemList(data).length;
}
