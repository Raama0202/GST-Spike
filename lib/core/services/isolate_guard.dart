import 'package:shared_preferences/shared_preferences.dart';

/// Coordinates the UI isolate and the WorkManager isolate, which must not have
/// the same Hive boxes open at once (Hive is not multi-isolate safe).
///
/// The UI isolate stamps a heartbeat while alive; the background worker skips
/// its run when the stamp is fresh and records when it did run, so the UI can
/// reload its boxes from disk afterwards. [SharedPreferencesAsync] is used
/// because the cached API would hide writes made by the other isolate.
abstract final class IsolateGuard {
  static const _heartbeatKey = 'fg_heartbeat_ms';
  static const _backgroundRunKey = 'bg_sync_ran_ms';
  static const heartbeatInterval = Duration(seconds: 30);
  static const foregroundWindow = Duration(minutes: 2);

  static SharedPreferencesAsync get _prefs => SharedPreferencesAsync();

  static Future<void> beat() async {
    try {
      await _prefs.setInt(
        _heartbeatKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  static Future<bool> foregroundActive() async {
    try {
      final stamp = await _prefs.getInt(_heartbeatKey);
      if (stamp == null) return false;
      final age = DateTime.now().millisecondsSinceEpoch - stamp;
      return age >= 0 && age < foregroundWindow.inMilliseconds;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markBackgroundRun() async {
    try {
      await _prefs.setInt(
        _backgroundRunKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  static Future<int?> lastBackgroundRun() async {
    try {
      return await _prefs.getInt(_backgroundRunKey);
    } catch (_) {
      return null;
    }
  }
}
