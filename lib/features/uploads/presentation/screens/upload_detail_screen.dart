import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:gst_expense_scanner/core/config/server_config.dart';
import 'package:gst_expense_scanner/core/errors/exceptions.dart';
import 'package:gst_expense_scanner/core/theme/glass.dart';
import 'package:gst_expense_scanner/features/home/presentation/providers/home_providers.dart';
import 'package:gst_expense_scanner/features/sync/presentation/sync_providers.dart';
import 'package:gst_expense_scanner/features/uploads/domain/repositories/invoice_repository.dart';
import 'package:gst_expense_scanner/shared/models/invoice_entity.dart';
import 'package:gst_expense_scanner/shared/widgets/app_scaffold.dart';
import 'package:gst_expense_scanner/shared/widgets/error_view.dart';
import 'package:gst_expense_scanner/shared/widgets/primary_button.dart';
import 'package:gst_expense_scanner/shared/widgets/status_chip.dart';

/// Opened from My Uploads with a local id, or from a notification with the
/// server id of an invoice that may not be on this phone yet.
class UploadDetailScreen extends ConsumerWidget {
  const UploadDetailScreen({super.key, required String this.localId})
    : serverId = null;

  const UploadDetailScreen.server({super.key, required String this.serverId})
    : localId = null;

  final String? localId;
  final String? serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverId = this.serverId;
    if (serverId != null) {
      final detail = ref.watch(serverInvoiceProvider(serverId));
      return AppScaffold(
        title: 'Upload detail',
        body: detail.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ErrorView(
            message: error is AppException
                ? error.failure.message
                : 'Could not load this invoice.',
            onRetry: () => ref.invalidate(serverInvoiceProvider(serverId)),
          ),
          data: (d) => _DetailBody(invoice: d.invoice, history: d.history),
        ),
      );
    }

    final localId = this.localId!;
    final detail = ref.watch(uploadDetailProvider(localId));
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
          final remoteId = invoice.serverId;
          if (remoteId == null) return _DetailBody(invoice: invoice);

          // Show the cached copy at once; the live copy adds history and a
          // fresh image link when the server is reachable.
          final live = ref.watch(serverInvoiceProvider(remoteId)).valueOrNull;
          return _DetailBody(
            invoice: live?.invoice ?? invoice,
            history: live?.history,
          );
        },
      ),
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({required this.invoice, this.history});

  final InvoiceEntity invoice;
  final List<InvoiceHistoryEntry>? history;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  bool _busy = false;

  InvoiceEntity get _invoice => widget.invoice;

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _changed() {
    final serverId = _invoice.serverId;
    if (serverId != null) ref.invalidate(serverInvoiceProvider(serverId));
    ref.read(syncStatusProvider.notifier)
      ..markChanged()
      ..nudge();
  }

  Future<void> _retry({bool duplicateOverride = false}) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(invoiceRepositoryProvider)
          .retryNow(_invoice.localId, duplicateOverride: duplicateOverride);
      _changed();
      if (mounted) _snack('Queued for upload');
    } catch (_) {
      if (mounted) _snack('Could not queue this invoice. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmOverride() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit anyway?'),
        content: const Text(
          'The server already has an invoice with the same vendor, number '
          'and amount. Submit only if this is a different bill.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit anyway'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _retry(duplicateOverride: true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this invoice?'),
        content: const Text(
          'It has not been uploaded. The scan will be removed from this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Brand.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(invoiceRepositoryProvider).deleteLocal(_invoice.localId);
      ref.read(syncStatusProvider.notifier).markChanged();
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _snack('Could not delete this invoice.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final invoice = _invoice;
    final history = widget.history;
    final remarks = invoice.adminRemarks;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (!invoice.isServerOnly) StatusChip.sync(invoice.syncStatus),
            StatusChip.approval(invoice.approvalStatus),
          ],
        ),
        if (invoice.syncStatus == SyncStatus.failed &&
            invoice.lastUploadError != null) ...[
          const SizedBox(height: 16),
          _Banner(
            color: Brand.danger,
            icon: Icons.error_outline_rounded,
            title: invoice.needsDuplicateOverride
                ? 'Possible duplicate'
                : 'Upload needs attention',
            body: invoice.lastUploadError!,
          ),
        ],
        if (remarks != null && remarks.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Banner(
            color: invoice.approvalStatus == ApprovalStatus.rejected
                ? Brand.danger
                : Brand.orange,
            icon: Icons.comment_rounded,
            title: 'Admin remarks',
            body: remarks,
          ),
        ],
        const SizedBox(height: 16),
        _InvoiceImage(invoice: invoice),
        const SizedBox(height: 16),
        Text('Invoice details', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        _DataSection(data: invoice.editedData),
        if (!invoice.isServerOnly) ...[
          const SizedBox(height: 20),
          Text('Scanned values', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          _DataSection(data: invoice.ocrData),
        ],
        if (history != null && history.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('History', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          _HistoryTimeline(entries: history),
        ],
        const SizedBox(height: 24),
        ..._actions(),
      ],
    );
  }

  List<Widget> _actions() {
    final invoice = _invoice;
    final actions = <Widget>[
      if (invoice.canResubmit)
        PrimaryButton(
          label: 'Edit & resubmit',
          icon: Icons.edit_rounded,
          onPressed: _busy
              ? null
              : () => context.push('/uploads/${invoice.localId}/resubmit'),
        ),
      if (invoice.needsDuplicateOverride)
        PrimaryButton(
          label: 'Submit anyway',
          icon: Icons.copy_all_rounded,
          loading: _busy,
          onPressed: _confirmOverride,
        )
      else if (invoice.syncStatus == SyncStatus.failed &&
          !invoice.isServerOnly)
        PrimaryButton(
          label: 'Retry now',
          icon: Icons.refresh_rounded,
          loading: _busy,
          onPressed: _retry,
        ),
      if (invoice.canDeleteLocally)
        OutlinedButton.icon(
          onPressed: _busy ? null : _delete,
          style: OutlinedButton.styleFrom(foregroundColor: Brand.danger),
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('Delete'),
        ),
    ];
    return [
      for (var i = 0; i < actions.length; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        actions[i],
      ],
    ];
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.icon,
    required this.title,
    required this.body,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      tint: color,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceImage extends StatelessWidget {
  const _InvoiceImage({required this.invoice});

  final InvoiceEntity invoice;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cacheWidth = (width * MediaQuery.devicePixelRatioOf(context)).round();
    final localPath =
        invoice.compressedImagePath ??
        invoice.originalImagePath ??
        invoice.thumbnailPath;
    final remote = ServerConfig.resolveMediaUrl(invoice.imageUrl);

    Widget? image;
    if (localPath != null && File(localPath).existsSync()) {
      image = Image.file(
        File(localPath),
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
      );
    } else if (remote != null) {
      image = Image.network(
        remote,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              ),
        errorBuilder: (context, _, _) => const SizedBox(
          height: 120,
          child: Center(child: Text('Image is not available right now.')),
        ),
      );
    }
    if (image == null) return const SizedBox.shrink();
    return ClipRRect(borderRadius: BorderRadius.circular(12), child: image);
  }
}

class _HistoryTimeline extends StatelessWidget {
  const _HistoryTimeline({required this.entries});

  final List<InvoiceHistoryEntry> entries;

  static String _label(String action) => switch (action.toLowerCase()) {
    'uploaded' || 'submitted' || 'created' => 'Submitted',
    'approved' => 'Approved',
    'rejected' => 'Rejected',
    'returned' => 'Returned for changes',
    'resubmitted' => 'Resubmitted',
    _ =>
      action.isEmpty
          ? 'Updated'
          : action[0].toUpperCase() + action.substring(1).replaceAll('_', ' '),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = DateFormat('dd MMM yyyy, hh:mm a');
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Icon(
                        Icons.circle,
                        size: 10,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _label(entry.action),
                            style: theme.textTheme.titleMedium,
                          ),
                          if (entry.byName != null || entry.at != null)
                            Text(
                              [
                                ?entry.byName,
                                if (entry.at != null) format.format(entry.at!),
                              ].join(' · '),
                              style: theme.textTheme.bodySmall,
                            ),
                          if (entry.remarks != null &&
                              entry.remarks!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(entry.remarks!),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
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
            if (data.igst != null && data.igst! > 0)
              _row('IGST', _money(data.igst))
            else ...[
              _row('CGST', _money(data.cgst)),
              _row('SGST', _money(data.sgst)),
            ],
            _row('Discount', _money(data.discount)),
            _row('Invoice value', _money(data.netAmount)),
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
