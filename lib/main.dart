import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gst_expense_scanner/app/app.dart';
import 'package:gst_expense_scanner/app/bootstrap.dart';
import 'package:gst_expense_scanner/core/di/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final container = ProviderContainer(overrides: appProviderOverrides);
  await bootstrap(container);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const GstExpenseApp(),
    ),
  );
}
