import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gst_expense_scanner/core/constants/app_constants.dart';
import 'package:gst_expense_scanner/core/theme/app_theme.dart';
import 'package:gst_expense_scanner/features/company_config/presentation/company_config_providers.dart';

import 'router.dart';

class GstExpenseApp extends ConsumerWidget {
  const GstExpenseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final brandColor = ref.watch(companyBrandColorProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(brandPrimary: brandColor),
      routerConfig: router,
    );
  }
}
