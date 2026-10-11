/// Compile-time and runtime environment configuration.
///
/// Pass secrets and endpoints via --dart-define, never commit them.
///
/// Example:
/// flutter run --dart-define=API_BASE_URL=https://api.example.com/v1 \
///             --dart-define=ENV=staging
class EnvConfig {
  EnvConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://gst-expense-scanner.onrender.com/v1',
  );

  static const String env = String.fromEnvironment(
    'ENV',
    defaultValue: 'production',
  );

  static const bool enableNetworkLogging = bool.fromEnvironment(
    'ENABLE_NETWORK_LOGGING',
    defaultValue: false,
  );

  static const String pinSha256Csv = String.fromEnvironment(
    'CERT_PINS_SHA256',
    defaultValue: '',
  );

  /// Lets the device change the API endpoint at runtime. Enable for demo and
  /// on-premise builds; keep disabled for Play Store builds so a stolen device
  /// cannot be pointed at an attacker-controlled server.
  static const bool allowServerOverride = bool.fromEnvironment(
    'ALLOW_SERVER_OVERRIDE',
    defaultValue: false,
  );

  static bool get isProduction => env == 'production';

  static List<String> get certificatePins => pinSha256Csv
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
}
