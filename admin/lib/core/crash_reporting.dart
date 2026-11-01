import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'constants.dart';

/// google_fonts downloads fonts at runtime and throws when offline; the text
/// simply keeps the platform font, so these are not crashes.
bool _isFontFetchFailure(Object error) {
  final text = error.toString();
  return text.contains('google_fonts') || text.contains('Failed to load font');
}

/// Installs uncaught-error hooks, then runs the app. Errors go to Sentry only
/// when the build defines `SENTRY_DSN`; otherwise they are logged.
Future<void> runWithCrashReporting(FutureOr<void> Function() appRunner) async {
  if (AppConstants.sentryDsn.isEmpty) {
    FlutterError.onError = (details) {
      if (_isFontFetchFailure(details.exception)) return;
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      if (!_isFontFetchFailure(error)) {
        debugPrint('Uncaught error: $error\n$stack');
      }
      return true;
    };
    await appRunner();
    return;
  }
  await SentryFlutter.init((options) {
    options
      ..dsn = AppConstants.sentryDsn
      ..environment = kReleaseMode ? 'production' : 'debug'
      ..sendDefaultPii = false
      ..tracesSampleRate = 0
      ..beforeSend = (event, hint) {
        final error = event.throwable;
        return error != null && _isFontFetchFailure(error) ? null : event;
      };
  }, appRunner: appRunner);
}
