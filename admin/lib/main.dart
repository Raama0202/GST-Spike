import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'app/app.dart';
import 'core/api_client.dart';
import 'core/server_config.dart';
import 'core/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SecureStore(
    const FlutterSecureStorage(
      aOptions: AndroidOptions(),
      webOptions: WebOptions(
        dbName: 'gst_expense_admin',
        publicKey: 'gst-expense-admin-session',
      ),
    ),
  );
  await ServerConfig.load(store);
  runApp(
    ProviderScope(
      overrides: [secureStoreProvider.overrideWithValue(store)],
      child: const GstExpenseAdminApp(),
    ),
  );
}
