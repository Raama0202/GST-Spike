import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api_client.dart';
import '../../core/file_share.dart';
import '../../core/format.dart';
import '../../core/glass.dart';
import '../../core/server_config.dart';
import '../../shared/widgets.dart';
import 'invoice_repository.dart';

/// Server limit per bulk-decision call.
const _bulkChunk = 100;

class InvoicesScreen extends ConsumerStatefulWidget {
  const InvoicesScreen({super.key});
  @override
  ConsumerState<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends ConsumerState<InvoicesScreen> {
  late final _search = TextEditingController(
    text: ref.read(invoiceFiltersProvider).query,
  );
  Timer? _debounce;
  final _selected = <String>{};
  bool _working = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  InvoiceFiltersController get _filters =>
      ref.read(invoiceFiltersProvider.notifier);

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _filters.update((f) => f.copyWith(query: value));
    });
  }

  Future<void> _pickDates(InvoiceFilters filters) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      // GST came into force on 1 July 2017.
      firstDate: DateTime(2017, 7),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: filters.dateFrom != null && filters.dateTo != null
          ? DateTimeRange(start: filters.dateFrom!, end: filters.dateTo!)
          : null,
      helpText: 'Invoice date range',
    );
    if (range == null) return;
    _filters.update(
      (f) => f.copyWith(dateFrom: range.start, dateTo: range.end),
    );
  }

  Future<void> _openFilterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _FilterSheet(),
    );
  }

  Future<void> _export(String format) async {
    setState(() => _working = true);
    try {
      final file = await ref
          .read(invoiceRepositoryProvider)
          .export(ref.read(invoiceFiltersProvider), format);
      if (!mounted) return;
      await shareFile(
        context,
        file.bytes,
        filename: file.filename,
        mimeType: format == 'xlsx' ? xlsxMime : csvMime,
      );
    } catch (error) {
      if (mounted) showSnack(context, apiError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _toggle(String id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });

  Future<void> _bulk(String status) async {
    final count = _selected.length;
    final noun = count == 1 ? 'invoice' : 'invoices';
    String? remarks;
    if (status == 'approved') {
      final ok = await confirmAction(
        context,
        title: 'Approve $count $noun?',
        message: 'Employees are notified of the decision.',
        confirmLabel: 'Approve',
      );
      if (!ok) return;
    } else {
      remarks = await promptRemarks(
        context,
        title: status == 'rejected'
            ? 'Reject $count $noun'
            : 'Return $count $noun',
        confirmLabel: status == 'rejected' ? 'Reject' : 'Return',
        required: true,
        message: status == 'returned'
            ? 'Employees can correct and resubmit returned invoices.'
            : null,
      );
      if (remarks == null) return;
    }
    if (!mounted) return;
    setState(() => _working = true);
    final ids = _selected.toList();
    var updated = 0;
    var skipped = 0;
    try {
      for (var i = 0; i < ids.length; i += _bulkChunk) {
        final chunk = ids.sublist(i, (i + _bulkChunk).clamp(0, ids.length));
        final result = await ref
            .read(invoiceRepositoryProvider)
            .bulkDecision(chunk, status, remarks);
        updated += result.updated;
        skipped += result.skipped;
      }
      if (!mounted) return;
      setState(_selected.clear);
      showSnack(
        context,
        skipped == 0
            ? 'Updated $updated $noun.'
            : 'Updated $updated, skipped $skipped already $status.',
      );
    } catch (error) {
      if (mounted) showSnack(context, apiError(error));
    } finally {
      if (mounted) {
        setState(() => _working = false);
        ref.invalidate(invoiceListProvider);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(invoiceFiltersProvider, (previous, next) {
      if (_selected.isNotEmpty) setState(_selected.clear);
      if (next.query != _search.text && next.query != previous?.query) {
        _search.text = next.query;
      }
    });
    final filters = ref.watch(invoiceFiltersProvider);
    final list = ref.watch(invoiceListProvider);
    final controller = ref.read(invoiceListProvider.notifier);
    final data = list.value;
    final selecting = _selected.isNotEmpty;

    return SliverPage(
      onRefresh: controller.refresh,
      onEndReached: controller.loadMore,
      slivers: [
        SliverToBoxAdapter(
          child: selecting
              ? _SelectionBar(
                  count: _selected.length,
                  busy: _working,
                  onClear: () => setState(_selected.clear),
                  onSelectAll: data == null
                      ? null
                      : () => setState(
                          () => _selected.addAll(
                            data.items.map((i) => i['id'].toString()),
                          ),
                        ),
                  onDecision: _bulk,
                )
              : PageHeader(
                  title: 'Invoices',
                  subtitle: 'Review uploads and track approval decisions.',
                  action: PopupMenuButton<String>(
                    tooltip: 'Export',
                    enabled: !_working,
                    icon: _working
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.ios_share_rounded),
                    onSelected: _export,
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'csv',
                        child: ListTile(
                          leading: Icon(Icons.description_outlined),
                          title: Text('Export CSV'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'xlsx',
                        child: ListTile(
                          leading: Icon(Icons.table_chart_outlined),
                          title: Text('Export Excel'),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: _onSearch,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search vendor, invoice no., GSTIN, employee',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: ValueListenableBuilder(
                      valueListenable: _search,
                      builder: (_, value, _) => value.text.isEmpty
                          ? const SizedBox.shrink()
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _search.clear();
                                _onSearch('');
                              },
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'Sort',
                icon: const Icon(Icons.sort_rounded),
                initialValue: filters.sort,
                onSelected: (sort) =>
                    _filters.update((f) => f.copyWith(sort: sort)),
                itemBuilder: (_) => [
                  for (final (value, label) in invoiceSorts)
                    CheckedPopupMenuItem(
                      value: value,
                      checked: filters.sort == value,
                      child: Text(label),
                    ),
                ],
              ),
              IconButton(
                tooltip: 'Branch and category filters',
                onPressed: _openFilterSheet,
                icon: Badge(
                  isLabelVisible:
                      filters.branchId != null || filters.categoryId != null,
                  child: const Icon(Icons.tune_rounded),
                ),
              ),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverToBoxAdapter(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, label) in invoiceStatuses)
                ChoiceChip(
                  label: Text(label),
                  selected: filters.status == value,
                  showCheckmark: false,
                  onSelected: (_) =>
                      _filters.update((f) => f.copyWith(status: value)),
                ),
              filters.dateFrom == null
                  ? ActionChip(
                      avatar: const Icon(Icons.date_range, size: 18),
                      label: const Text('Any date'),
                      onPressed: () => _pickDates(filters),
                    )
                  : InputChip(
                      avatar: const Icon(Icons.date_range, size: 18),
                      label: Text(
                        '${DateFormat('d MMM').format(filters.dateFrom!)} – '
                        '${DateFormat('d MMM yy').format(filters.dateTo!)}',
                      ),
                      onPressed: () => _pickDates(filters),
                      onDeleted: () => _filters.update(
                        (f) => f.copyWith(dateFrom: null, dateTo: null),
                      ),
                    ),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        if (list.isLoading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(),
            ),
          ),
        if (list.hasError && data == null)
          SliverToBoxAdapter(
            child: Card(
              child: ErrorPanel(
                message: apiError(list.error!),
                onRetry: controller.refresh,
              ),
            ),
          )
        else if (data != null && data.items.isEmpty)
          const SliverToBoxAdapter(
            child: Card(
              child: EmptyPanel(
                icon: Icons.receipt_long_outlined,
                title: 'No invoices in this view',
                message: 'Try another status, date range or search.',
              ),
            ),
          )
        else if (data != null) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                selecting
                    ? 'Tap invoices to add or remove them'
                    : 'Showing ${data.items.length} of ${data.total} · '
                          'long-press to select',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          SliverCard(
            sliver: SliverList.separated(
              itemCount: data.items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = data.items[index];
                final id = item['id'].toString();
                return _InvoiceTile(
                  item: item,
                  selecting: selecting,
                  selected: _selected.contains(id),
                  onTap: () =>
                      selecting ? _toggle(id) : context.push('/invoices/$id'),
                  onLongPress: () => _toggle(id),
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: LoadMoreFooter(
              loading: data.loadingMore,
              error: data.moreError,
              onRetry: controller.retryMore,
            ),
          ),
        ],
      ],
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.busy,
    required this.onClear,
    required this.onSelectAll,
    required this.onDecision,
  });
  final int count;
  final bool busy;
  final VoidCallback onClear;
  final VoidCallback? onSelectAll;
  final ValueChanged<String> onDecision;

  @override
  Widget build(BuildContext context) => GlassCard(
    padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Clear selection',
              onPressed: busy ? null : onClear,
              icon: const Icon(Icons.close),
            ),
            Expanded(
              child: Text(
                '$count selected',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton(
              onPressed: busy ? null : onSelectAll,
              child: const Text('Select all loaded'),
            ),
          ],
        ),
        if (busy) const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : () => onDecision('approved'),
              icon: const Icon(Icons.check),
              label: const Text('Approve'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : () => onDecision('returned'),
              icon: const Icon(Icons.undo),
              label: const Text('Return'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : () => onDecision('rejected'),
              icon: const Icon(Icons.close),
              label: const Text('Reject'),
            ),
          ],
        ),
      ],
    ),
  );
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({
    required this.item,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });
  final Map<String, dynamic> item;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final employee = item['employeeName']?.toString();
    final code = item['employeeCode']?.toString();
    final who = [
      if (employee != null && employee.isNotEmpty)
        code != null && code.isNotEmpty ? '$employee ($code)' : employee,
      item['branchName'],
      item['categoryName'],
    ].where((e) => e != null && '$e'.isNotEmpty).join(' • ');
    final thumb = ServerConfig.absoluteUrl(
      (item['thumbnailUrl'] ?? item['imageUrl'])?.toString(),
    );
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        selected: selected,
        isThreeLine: who.isNotEmpty,
        leading: selecting
            ? Checkbox(value: selected, onChanged: (_) => onTap())
            : _Thumbnail(url: thumb),
        title: Text(
          invoiceVendor(item),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            '${item['invoiceNumber'] ?? 'No invoice no.'} • '
                '${formatDate(item['invoiceDate'] ?? item['uploadedAt'])}',
            if (who.isNotEmpty) who,
          ].join('\n'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatInr(invoiceAmount(item)),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            StatusPill(invoiceStatus(item)),
          ],
        ),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.url});
  final String? url;
  @override
  Widget build(BuildContext context) {
    const placeholder = IconBadge(
      icon: Icons.receipt_long_rounded,
      color: Brand.indigo,
      size: 44,
    );
    if (url == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        imageUrl: url!,
        cacheKey: ServerConfig.mediaCacheKey(url!),
        width: 44,
        height: 44,
        memCacheWidth: 132,
        fit: BoxFit.cover,
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
      ),
    );
  }
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet();
  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late String? _branchId = ref.read(invoiceFiltersProvider).branchId;
  late String? _categoryId = ref.read(invoiceFiltersProvider).categoryId;

  Widget _dropdown({
    required String label,
    required AsyncValue<List<Map<String, dynamic>>> source,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) => source.when(
    loading: () => const LinearProgressIndicator(),
    error: (error, _) => Text('$label: ${apiError(error)}'),
    data: (items) {
      final known = items.any((i) => i['id'] == value);
      return DropdownButtonFormField<String?>(
        initialValue: known ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          DropdownMenuItem(
            value: null,
            child: Text('All ${label.toLowerCase()}s'),
          ),
          for (final item in items)
            DropdownMenuItem(
              value: item['id'].toString(),
              child: Text(
                item['name']?.toString() ?? '—',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: onChanged,
      );
    },
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Filters', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          _dropdown(
            label: 'Branch',
            source: ref.watch(invoiceBranchesProvider),
            value: _branchId,
            onChanged: (v) => setState(() => _branchId = v),
          ),
          const SizedBox(height: 14),
          _dropdown(
            label: 'Category',
            source: ref.watch(invoiceCategoriesProvider),
            value: _categoryId,
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              TextButton(
                onPressed: () => setState(() {
                  _branchId = null;
                  _categoryId = null;
                }),
                child: const Text('Clear'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  ref
                      .read(invoiceFiltersProvider.notifier)
                      .update(
                        (f) => f.copyWith(
                          branchId: _branchId,
                          categoryId: _categoryId,
                        ),
                      );
                  Navigator.pop(context);
                },
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
