import '../constants/app_constants.dart';
import '../constants/env_config.dart';
import '../security/secure_storage_service.dart';

/// The API endpoint actually in use, which may differ from the compiled-in one.
///
/// Demo tunnels and on-premise installations change hostnames often; without a
/// runtime override every new URL would require rebuilding and redistributing
/// the APK. The override is ignored unless [EnvConfig.allowServerOverride] is
/// set at build time.
class ServerConfig {
  ServerConfig._();

  static String _baseUrl = EnvConfig.apiBaseUrl;

  /// Endpoint every network call should use.
  static String get baseUrl => _baseUrl;

  /// Endpoint compiled into this build, used as the reset target.
  static String get compiledBaseUrl => EnvConfig.apiBaseUrl;

  static bool get isOverridden => _baseUrl != EnvConfig.apiBaseUrl;

  static bool get canOverride => EnvConfig.allowServerOverride;

  /// Host shown in the UI, e.g. `demo.trycloudflare.com`.
  static String get displayHost => Uri.tryParse(_baseUrl)?.host ?? _baseUrl;

  static Future<void> load(SecureStorageService storage) async {
    if (!canOverride) {
      _baseUrl = EnvConfig.apiBaseUrl;
      return;
    }
    final saved = await storage.read(StorageKeys.apiBaseUrlOverride);
    final normalized = saved == null ? null : normalize(saved);
    _baseUrl = normalized ?? EnvConfig.apiBaseUrl;
  }

  /// Persists [input] and returns the normalized URL, or null if unusable.
  static Future<String?> save(
    SecureStorageService storage,
    String input,
  ) async {
    if (!canOverride) return null;
    final normalized = normalize(input);
    if (normalized == null) return null;
    await storage.write(StorageKeys.apiBaseUrlOverride, normalized);
    _baseUrl = normalized;
    return normalized;
  }

  static Future<void> reset(SecureStorageService storage) async {
    await storage.delete(StorageKeys.apiBaseUrlOverride);
    _baseUrl = EnvConfig.apiBaseUrl;
  }

  /// Accepts what a person would realistically paste — a bare host, a host with
  /// a port, or a full URL — and returns a canonical API base URL.
  /// Returns null when the value cannot be used.
  static String? normalize(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'https://$text';

    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;

    var path = uri.path.replaceAll(RegExp(r'/+$'), '');
    // A bare host is almost always meant as the versioned API root.
    if (path.isEmpty) path = '/v1';

    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
    ).toString();
  }
}
