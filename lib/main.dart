import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gst_expense_scanner/app/app.dart';
import 'package:gst_expense_scanner/app/bootstrap.dart';
import 'package:gst_expense_scanner/core/di/providers.dart';
import 'package:gst_expense_scanner/core/services/crash_reporter.dart';

Future<void> main() async {
  await CrashReporter.run(() async {
    WidgetsFlutterBinding.ensureInitialized();

    final container = ProviderContainer(overrides: appProviderOverrides);
    try {
      await bootstrap(container);
    } catch (error, stack) {
      CrashReporter.record(error, stack, reason: 'bootstrap');
      runApp(StartupErrorApp(error: error));
      return;
    }

    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const GstExpenseApp(),
      ),
    );
    unawaited(startServices(container));
  });
}
