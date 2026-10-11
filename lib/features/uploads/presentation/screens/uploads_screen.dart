import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:gst_expense_scanner/features/uploads/presentation/providers/uploads_providers.dart';
import 'package:gst_expense_scanner/shared/widgets/app_scaffold.dart';
import 'package:gst_expense_scanner/shared/widgets/error_view.dart';
import 'package:gst_expense_scanner/shared/widgets/status_chip.dart';

class UploadsScreen extends ConsumerWidget {
  const UploadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uploads = ref.watch(uploadsListProvider);
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'My uploads',
      body: uploads.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(
          message: error.toString(),
          onRetry: () => ref.invalidate(uploadsListProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Text(
                'No uploads yet.\nScan an invoice to get started.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(uploadsListProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final invoice = items[index];
                final data = invoice.displayData;
                final date = data.invoiceDate ?? invoice.createdAt;
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    title: Text(
                      data.vendorName ?? 'Unknown vendor',
                      style: theme.textTheme.titleLarge,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          '${data.invoiceNumber ?? 'No number'} · ${DateFormat('dd MMM yyyy').format(date)}',
                        ),
                        if (data.netAmount != null)
                          Text('₹ ${data.netAmount!.toStringAsFixed(2)}'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            StatusChip.sync(invoice.syncStatus),
                            StatusChip.approval(invoice.approvalStatus),
                          ],
                        ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/uploads/${invoice.localId}'),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
