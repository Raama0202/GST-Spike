import 'dart:async';

import 'package:flutter/foundation.dart';

typedef CrashSink =
    void Function(Object error, StackTrace? stack, {String? reason});

/// Routes uncaught Flutter and platform errors to one place. It only logs
/// today; set [sink] at startup to forward to a crash service.
abstract final class CrashReporter {
  static CrashSink? sink;

  static Future<void> run(Future<void> Function() appRunner) async {
    _installHandlers();
    await appRunner();
  }

  static void _installHandlers() {
    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      (previousFlutter ?? FlutterError.presentError)(details);
      record(details.exception, details.stack, reason: 'flutter');
    };
    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack, reason: 'platform');
      previousPlatform?.call(error, stack);
      return true;
    };
  }

  /// Also for caught-but-unexpected errors worth seeing in crash reports.
  static void record(Object error, StackTrace? stack, {String? reason}) {
    debugPrint('[crash]${reason == null ? '' : ' $reason:'} $error');
    if (stack != null && kDebugMode) debugPrintStack(stackTrace: stack);
    try {
      sink?.call(error, stack, reason: reason);
    } catch (_) {}
  }
}
