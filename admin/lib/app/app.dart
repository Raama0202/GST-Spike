import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import 'router.dart';

class GstExpenseAdminApp extends ConsumerWidget {
  const GstExpenseAdminApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: AppConstants.appName,
    debugShowCheckedModeBanner: false,
    theme: AdminTheme.light,
    darkTheme: AdminTheme.light,
    themeMode: ThemeMode.light,
    routerConfig: ref.watch(routerProvider),
  );
}
