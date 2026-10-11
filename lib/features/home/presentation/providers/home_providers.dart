import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gst_expense_scanner/core/di/providers.dart';
import 'package:gst_expense_scanner/features/auth/presentation/providers/auth_providers.dart';
import 'package:gst_expense_scanner/features/company_config/presentation/company_config_providers.dart';
import 'package:gst_expense_scanner/features/sync/presentation/sync_providers.dart';
import 'package:gst_expense_scanner/shared/models/invoice_entity.dart';

final homeTodayUploadCountProvider = FutureProvider<int>((ref) async {
  ref.watch(syncStatusProvider.select((s) => s.revision));
  final repo = ref.watch(invoiceRepositoryProvider);
  final invoices = await repo.list();
  final now = DateTime.now();
  return invoices.where((invoice) {
    return invoice.createdAt.year == now.year &&
        invoice.createdAt.month == now.month &&
        invoice.createdAt.day == now.day;
  }).length;
});

final homePendingSyncCountProvider = Provider<int>((ref) {
  return ref.watch(syncStatusProvider).pendingCount;
});

final homeEmployeeNameProvider = Provider<String>((ref) {
  final auth = ref.watch(authStateProvider);
  if (auth is AuthAuthenticated) return auth.employee.name;
  return '';
});

final homeCompanyNameProvider = Provider<String>((ref) {
  final config = ref.watch(activeCompanyConfigProvider);
  if (config != null) return config.companyName;
  final auth = ref.watch(authStateProvider);
  if (auth is AuthAuthenticated) return auth.employee.companyName;
  return '';
});

final uploadsListProvider = FutureProvider<List<InvoiceEntity>>((ref) async {
  ref.watch(syncStatusProvider.select((s) => s.revision));
  final repo = ref.watch(invoiceRepositoryProvider);
  return repo.list();
});

final uploadDetailProvider = FutureProvider.family<InvoiceEntity?, String>((
  ref,
  localId,
) async {
  ref.watch(syncStatusProvider.select((s) => s.revision));
  final repo = ref.watch(invoiceRepositoryProvider);
  return repo.getById(localId);
});
