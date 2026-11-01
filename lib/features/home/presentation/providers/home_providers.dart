import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gst_expense_scanner/features/auth/presentation/providers/auth_providers.dart';
import 'package:gst_expense_scanner/features/company_config/presentation/company_config_providers.dart';
import 'package:gst_expense_scanner/features/sync/presentation/sync_providers.dart';
import 'package:gst_expense_scanner/features/uploads/domain/repositories/invoice_repository.dart';
import 'package:gst_expense_scanner/shared/models/invoice_entity.dart';

final homeTodayUploadCountProvider = FutureProvider<int>((ref) async {
  final invoices = await ref.watch(uploadsListProvider.future);
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

/// Local invoices the sync engine gave up on (duplicate, rejected, …).
final homeNeedsAttentionCountProvider = Provider<int>((ref) {
  final invoices = ref.watch(uploadsListProvider).valueOrNull ?? const [];
  return invoices
      .where((i) => i.syncStatus == SyncStatus.failed && !i.isServerOnly)
      .length;
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

/// Live server copy (status, fresh image link, history) of an uploaded
/// invoice. Not cached across screens: media links are short-lived.
final serverInvoiceProvider = FutureProvider.autoDispose
    .family<ServerInvoiceDetail, String>((ref, serverId) {
      return ref.watch(invoiceRepositoryProvider).fetchServerInvoice(serverId);
    });
