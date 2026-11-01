import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:gst_expense_scanner/core/config/server_config.dart';
import 'package:gst_expense_scanner/core/theme/glass.dart';
import 'package:gst_expense_scanner/features/sync/presentation/sync_providers.dart';
import 'package:gst_expense_scanner/features/uploads/presentation/providers/uploads_providers.dart';
import 'package:gst_expense_scanner/shared/models/invoice_entity.dart';
import 'package:gst_expense_scanner/shared/widgets/app_scaffold.dart';
import 'package:gst_expense_scanner/shared/widgets/error_view.dart';
import 'package:gst_expense_scanner/shared/widgets/status_chip.dart';

enum UploadFilter {
  all('All'),
  pending('Pending'),
  failed('Needs attention'),
  submitted('Submitted'),
  approved('Approved'),
  rejected('Rejected'),
  returned('Returned');

  const UploadFilter(this.label);

  final String label;

  static UploadFilter parse(String? value) => UploadFilter.values.firstWhere(
    (f) => f.name == value,
    orElse: () => UploadFilter.all,
  );

  bool matches(InvoiceEntity invoice) => switch (this) {
    UploadFilter.all => true,
    UploadFilter.pending =>
      invoice.syncStatus == SyncStatus.pending ||
          invoice.syncStatus == SyncStatus.uploading,
    UploadFilter.failed =>
      invoice.syncStatus == SyncStatus.failed && !invoice.isServerOnly,
    UploadFilter.submitted =>
      invoice.syncStatus == SyncStatus.uploaded &&
          (invoice.approvalStatus == ApprovalStatus.pending ||
              invoice.approvalStatus == ApprovalStatus.uploaded),
    UploadFilter.approved => invoice.approvalStatus == ApprovalStatus.approved,
    UploadFilter.rejected => invoice.approvalStatus == ApprovalStatus.rejected,
    UploadFilter.returned => invoice.approvalStatus == ApprovalStatus.returned,
  };
}

class UploadsScreen extends ConsumerStatefulWidget {
  const UploadsScreen({super.key, this.initialFilter});

  final String? initialFilter;

  @override
  ConsumerState<UploadsScreen> createState() => _UploadsScreenState();
}

class _UploadsScreenState extends ConsumerState<UploadsScreen> {
  final _searchController = TextEditingController();
  late UploadFilter _filter = UploadFilter.parse(widget.initialFilter);
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesQuery(InvoiceEntity invoice) {
    if (_query.isEmpty) return true;
    final data = invoice.displayData;
    final haystack = [
      data.vendorName,
      data.invoiceNumber,
      data.gstin,
      data.netAmount?.toStringAsFixed(2),
    ].whereType<String>().join(' ').toLowerCase();
    return haystack.contains(_query);
  }

  Future<void> _refresh() =>
      ref.read(syncStatusProvider.notifier).syncNow();

  @override
  Widget build(BuildContext context) {
    final uploads = ref.watch(uploadsListProvider);
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'My uploads',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search vendor, invoice no. or GSTIN',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: UploadFilter.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = UploadFilter.values[index];
                return ChoiceChip(
                  label: Text(filter.label),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                );
              },
            ),
          ),
          Expanded(
            child: uploads.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => ErrorView(
                message: error.toString(),
                onRetry: () => ref.invalidate(uploadsListProvider),
              ),
              data: (all) {
                final items = all
                    .where((i) => _filter.matches(i) && _matchesQuery(i))
                    .toList();
                if (items.isEmpty) {
                  final message = all.isEmpty
                      ? 'No uploads yet.\nScan an invoice to get started.'
                      : 'No invoices match this filter.';
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: SizedBox(
                          height: constraints.maxHeight,
                          child: Center(
                            child: Text(
                              message,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _UploadTile(invoice: items[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadTile extends StatelessWidget {
  const _UploadTile({required this.invoice});

  final InvoiceEntity invoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = invoice.displayData;
    final date = data.invoiceDate ?? invoice.createdAt;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(GlassMetrics.radius),
        onTap: () => context.push('/uploads/${invoice.localId}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InvoiceThumbnail(invoice: invoice, size: 64),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.vendorName ?? 'Unknown vendor',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${data.invoiceNumber ?? 'No number'} · '
                      '${DateFormat('dd MMM yyyy').format(date)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    if (data.netAmount != null)
                      Text(
                        '₹ ${data.netAmount!.toStringAsFixed(2)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (!invoice.isServerOnly)
                          StatusChip.sync(invoice.syncStatus),
                        StatusChip.approval(invoice.approvalStatus),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// Local thumbnail when the file is on this phone, otherwise the signed
/// server link. Decoded at display size to keep long lists light.
class InvoiceThumbnail extends StatelessWidget {
  const InvoiceThumbnail({super.key, required this.invoice, this.size = 64});

  final InvoiceEntity invoice;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cacheWidth = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.receipt_long_rounded,
        color: GlassPalette.muted(context),
      ),
    );
    Widget fallback(BuildContext context, Object _, StackTrace? _) =>
        placeholder;

    final localPath = invoice.thumbnailPath ?? invoice.compressedImagePath;
    final remote = ServerConfig.resolveMediaUrl(
      invoice.thumbnailUrl ?? invoice.imageUrl,
    );
    final Widget image;
    if (localPath != null) {
      image = Image.file(
        File(localPath),
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        errorBuilder: remote == null
            ? fallback
            : (context, _, _) => Image.network(
                remote,
                fit: BoxFit.cover,
                cacheWidth: cacheWidth,
                errorBuilder: fallback,
              ),
      );
    } else if (remote != null) {
      image = Image.network(
        remote,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        errorBuilder: fallback,
      );
    } else {
      image = placeholder;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox.square(dimension: size, child: image),
    );
  }
}
