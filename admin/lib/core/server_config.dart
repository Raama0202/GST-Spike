import 'constants.dart';
import 'storage.dart';

/// Runtime API endpoint, which may differ from the compiled-in default.
class ServerConfig {
  ServerConfig._();

  static String _baseUrl = AppConstants.apiBaseUrl;

  static String get baseUrl => _baseUrl;
  static String get compiledBaseUrl => AppConstants.apiBaseUrl;
  static bool get isOverridden => _baseUrl != AppConstants.apiBaseUrl;
  static bool get canOverride => AppConstants.allowServerOverride;
  static String get displayHost => Uri.tryParse(_baseUrl)?.host ?? _baseUrl;

  static Future<void> load(SecureStore store) async {
    if (!canOverride) {
      _baseUrl = AppConstants.apiBaseUrl;
      return;
    }
    final saved = await store.apiBaseUrlOverride;
    final normalized = saved == null ? null : normalize(saved);
    _baseUrl = normalized ?? AppConstants.apiBaseUrl;
  }

  static Future<String?> save(SecureStore store, String input) async {
    if (!canOverride) return null;
    final normalized = normalize(input);
    if (normalized == null) return null;
    await store.setApiBaseUrlOverride(normalized);
    _baseUrl = normalized;
    return normalized;
  }

  static Future<void> reset(SecureStore store) async {
    await store.clearApiBaseUrlOverride();
    _baseUrl = AppConstants.apiBaseUrl;
  }

  /// Signed media URLs change on every fetch; cache by path so images are
  /// downloaded once.
  static String mediaCacheKey(String url) => url.split('?').first;

  /// The API returns signed media paths like `/v1/media/...` relative to the
  /// server root; R2 presigned URLs are already absolute.
  static String? absoluteUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final base = Uri.tryParse(_baseUrl);
    if (base == null) return path;
    final origin = Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
    );
    return origin.resolve(path).toString();
  }

  static String? normalize(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'https://$text';

    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;

    var path = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (path.isEmpty) path = '/v1';

    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
    ).toString();
  }
}
