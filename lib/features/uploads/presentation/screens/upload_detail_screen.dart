import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:gst_expense_scanner/features/uploads/presentation/providers/uploads_providers.dart';
import 'package:gst_expense_scanner/shared/models/invoice_entity.dart';
import 'package:gst_expense_scanner/shared/widgets/app_scaffold.dart';
import 'package:gst_expense_scanner/shared/widgets/error_view.dart';
import 'package:gst_expense_scanner/shared/widgets/status_chip.dart';

class UploadDetailScreen extends ConsumerWidget {
  const UploadDetailScreen({super.key, required this.localId});

  final String localId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(uploadDetailProvider(localId));
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Upload detail',
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(
          message: error.toString(),
          onRetry: () => ref.invalidate(uploadDetailProvider(localId)),
        ),
        data: (invoice) {
          if (invoice == null) {
            return const ErrorView(message: 'Invoice not found.');
          }

          final imagePath = invoice.compressedImagePath ??
              invoice.originalImagePath ??
              invoice.thumbnailPath;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Wrap(
                spacing: 8,
                children: [
                  StatusChip.sync(invoice.syncStatus),
                  StatusChip.approval(invoice.approvalStatus),
                ],
              ),
              if (imagePath != null && File(imagePath).existsSync()) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(imagePath),
                    fit: BoxFit.cover,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text('Edited values', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              _DataSection(data: invoice.editedData),
              const SizedBox(height: 20),
              Text('OCR values', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              _DataSection(data: invoice.ocrData),
              if (invoice.adminRemarks != null &&
                  invoice.adminRemarks!.isNotEmpty) ...[
                const SizedBox(height: 20),
                Card(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Admin remarks',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(invoice.adminRemarks!),
                      ],
                    ),
                  ),
                ),
              ],
              if (invoice.lastUploadError != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Upload error: ${invoice.lastUploadError}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DataSection extends StatelessWidget {
  const _DataSection({required this.data});

  final InvoiceFieldData data;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _row('Vendor', data.vendorName),
            _row('GSTIN', data.gstin),
            _row('Invoice #', data.invoiceNumber),
            _row(
              'Date',
              data.invoiceDate != null
                  ? DateFormat('dd MMM yyyy').format(data.invoiceDate!)
                  : null,
            ),
            _row('Taxable', _money(data.taxableValue)),
            _row('CGST', _money(data.cgst)),
            _row('SGST', _money(data.sgst)),
            _row('Discount', _money(data.discount)),
            _row('Net', _money(data.netAmount)),
            _row('Category', data.expenseCategoryName),
            _row('Remarks', data.remarks),
          ],
        ),
      ),
    );
  }

  String? _money(double? value) =>
      value == null ? null : '₹ ${value.toStringAsFixed(2)}';

  Widget _row(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value ?? '—')),
        ],
      ),
    );
  }
}
