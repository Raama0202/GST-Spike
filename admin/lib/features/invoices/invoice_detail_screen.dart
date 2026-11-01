import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/glass.dart';
import '../../core/server_config.dart';
import '../../core/validators.dart';
import '../../shared/widgets.dart';
import 'invoice_repository.dart';

/// (endpoint action, resulting status, button label, icon)
const _decisions = [
  ('approve', 'approved', 'Approve', Icons.check),
  ('return', 'returned', 'Return', Icons.undo),
  ('reject', 'rejected', 'Reject', Icons.close),
];

class InvoiceDetailScreen extends ConsumerWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId});
  final String invoiceId;

  void _refreshAll(WidgetRef ref) {
    ref.invalidate(invoiceDetailProvider(invoiceId));
    ref.invalidate(invoiceListProvider);
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    String status,
    (String, String, String, IconData) decision,
  ) async {
    final (action, target, label, _) = decision;
    if (status != 'pending') {
      final ok = await confirmAction(
        context,
        title: 'Change decision?',
        message:
            'This invoice is already $status. Change it to $target? '
            'The employee will be notified.',
        confirmLabel: 'Change to $target',
      );
      if (!ok || !context.mounted) return;
    }
    final remarks = await promptRemarks(
      context,
      title: '$label invoice',
      confirmLabel: label,
      required: action != 'approve',
      message: action == 'return'
          ? 'The employee can correct and resubmit a returned invoice.'
          : null,
    );
    if (remarks == null || !context.mounted) return;
    try {
      await ref
          .read(invoiceRepositoryProvider)
          .decide(invoiceId, action, remarks);
      if (!context.mounted) return;
      _refreshAll(ref);
      showSnack(context, 'Invoice $target.');
    } catch (error) {
      if (context.mounted) showSnack(context, apiError(error));
    }
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> item,
  ) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditInvoiceSheet(invoiceId: invoiceId, item: item),
    );
    if (saved == true && context.mounted) {
      _refreshAll(ref);
      showSnack(context, 'Invoice updated.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(invoiceDetailProvider(invoiceId));
    final item = detail.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice review'),
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/invoices'),
        ),
        actions: [
          if (item != null)
            IconButton(
              tooltip: 'Edit fields',
              onPressed: () => _edit(context, ref, item),
              icon: const Icon(Icons.edit_outlined),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: detail.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorPanel(
          message: apiError(error),
          onRetry: () => ref.invalidate(invoiceDetailProvider(invoiceId)),
        ),
        data: (item) => ContentPage(
          onRefresh: () => ref.refresh(invoiceDetailProvider(invoiceId).future),
          child: _body(context, ref, item),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, Map<String, dynamic> item) {
    final status = invoiceStatus(item);
    final ocr = item['ocrData'] is Map
        ? Map<String, dynamic>.from(item['ocrData'] as Map)
        : <String, dynamic>{};
    final edited = item['editedData'] is Map
        ? Map<String, dynamic>.from(item['editedData'] as Map)
        : <String, dynamic>{};
    final image = ServerConfig.absoluteUrl(
      (item['imageUrl'] ?? item['originalImageUrl'] ?? item['thumbnailUrl'])
          ?.toString(),
    );
    final fullImage =
        ServerConfig.absoluteUrl(item['originalImageUrl']?.toString()) ?? image;
    final history = item['history'] is List
        ? (item['history'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : const <Map<String, dynamic>>[];
    void reload() => ref.invalidate(invoiceDetailProvider(invoiceId));

    final imagePanel = _ImagePanel(
      url: image,
      onOpen: fullImage == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => _ImageViewer(url: fullImage, onRetry: reload),
              ),
            ),
      onRetry: reload,
    );
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryCard(item: item, status: status),
        const SizedBox(height: 16),
        _GstinCard(invoiceId: invoiceId, item: item),
      ],
    );
    final decisions = Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.end,
      children: [
        for (final decision in _decisions)
          if (decision.$2 != status)
            decision.$1 == 'approve'
                ? FilledButton.icon(
                    onPressed: () => _decide(context, ref, status, decision),
                    icon: Icon(decision.$4),
                    label: Text(decision.$3),
                  )
                : OutlinedButton.icon(
                    onPressed: () => _decide(context, ref, status, decision),
                    icon: Icon(decision.$4),
                    label: Text(decision.$3),
                  ),
      ],
    );
    final dataPanel = Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Captured vs corrected',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            _ComparisonTable(ocr: ocr, edited: edited),
          ],
        ),
      ),
    );
    final historyPanel = Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('History', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            if (history.isEmpty)
              const Text('No history recorded yet.')
            else
              for (var i = 0; i < history.length; i++)
                _HistoryEntry(entry: history[i], last: i == history.length - 1),
          ],
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 850) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              summary,
              const SizedBox(height: 16),
              decisions,
              const SizedBox(height: 16),
              imagePanel,
              const SizedBox(height: 16),
              dataPanel,
              const SizedBox(height: 16),
              historyPanel,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [imagePanel, const SizedBox(height: 16), dataPanel],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  summary,
                  const SizedBox(height: 16),
                  decisions,
                  const SizedBox(height: 16),
                  historyPanel,
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.item, required this.status});
  final Map<String, dynamic> item;
  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fields = invoiceFields(item);
    final employee = item['employeeName']?.toString();
    final code = item['employeeCode']?.toString();
    final rows = [
      ('Invoice no.', item['invoiceNumber'] ?? fields['invoiceNumber']),
      (
        'Invoice date',
        formatDate(item['invoiceDate'] ?? fields['invoiceDate']),
      ),
      ('GSTIN', item['gstin'] ?? fields['gstin']),
      (
        'Employee',
        employee == null
            ? null
            : code == null || code.isEmpty
            ? employee
            : '$employee ($code)',
      ),
      ('Branch', item['branchName']),
      ('Category', item['categoryName']),
      ('Uploaded', formatDateTime(item['uploadedAt'])),
      if (item['reviewedAt'] != null)
        ('Reviewed', formatDateTime(item['reviewedAt'])),
    ];
    final remarks = item['adminRemarks']?.toString();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    invoiceVendor(item),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const SizedBox(width: 8),
                StatusPill(status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              formatInr(invoiceAmount(item)),
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 14),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        label,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        value == null || '$value'.isEmpty ? '—' : '$value',
                      ),
                    ),
                  ],
                ),
              ),
            if (remarks != null && remarks.isNotEmpty) ...[
              const Divider(height: 24),
              Text('Admin remarks', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(remarks),
            ],
          ],
        ),
      ),
    );
  }
}

/// Supplier GSTIN status on the GST portal, checked in the background after
/// upload, with a manual re-check.
class _GstinCard extends ConsumerStatefulWidget {
  const _GstinCard({required this.invoiceId, required this.item});
  final String invoiceId;
  final Map<String, dynamic> item;

  @override
  ConsumerState<_GstinCard> createState() => _GstinCardState();
}

class _GstinCardState extends ConsumerState<_GstinCard> {
  bool _busy = false;

  static const _labels = {
    'active': 'Active on GST portal',
    'cancelled': 'GSTIN cancelled',
    'suspended': 'GSTIN suspended',
    'inactive': 'GSTIN inactive',
    'not_found': 'Not found on GST portal',
    'invalid_format': 'Invalid GSTIN',
    'unverified': 'Not verified',
  };

  Future<void> _verify() async {
    setState(() => _busy = true);
    try {
      final updated = await ref
          .read(invoiceRepositoryProvider)
          .verifyGstin(widget.invoiceId);
      if (!mounted) return;
      ref.invalidate(invoiceDetailProvider(widget.invoiceId));
      final status = (updated['gstinCheck'] as Map?)?['status']?.toString();
      showSnack(context, _labels[status] ?? 'GSTIN checked.');
    } catch (error) {
      if (mounted) showSnack(context, apiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gstin = (widget.item['gstin'] ?? invoiceFields(widget.item)['gstin'])
        ?.toString();
    final check = widget.item['gstinCheck'] is Map
        ? Map<String, dynamic>.from(widget.item['gstinCheck'] as Map)
        : null;
    final status = check?['status']?.toString();
    final color = switch (status) {
      'active' => Brand.success,
      'inactive' => Brand.warning,
      'cancelled' || 'suspended' || 'not_found' || 'invalid_format' =>
        Brand.danger,
      _ => Brand.muted,
    };
    final legalName = check?['legalName']?.toString();
    final tradeName = check?['tradeName']?.toString();
    final message = check?['message']?.toString();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Supplier GSTIN',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (gstin != null && gstin.isNotEmpty)
                  TextButton.icon(
                    onPressed: _busy ? null : _verify,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_user_outlined, size: 18),
                    label: const Text('Verify with GST portal'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (gstin == null || gstin.isEmpty)
              const Text('No GSTIN on this bill.')
            else if (check == null)
              const Text('Checking with the GST portal… pull to refresh.')
            else ...[
              GlassPill(
                label: _labels[status] ?? 'Not verified',
                color: color,
                icon: status == 'active'
                    ? Icons.verified_rounded
                    : Icons.info_outline_rounded,
              ),
              if (legalName != null) ...[
                const SizedBox(height: 10),
                SelectableText(legalName, style: theme.textTheme.bodyLarge),
              ],
              if (tradeName != null && tradeName != legalName)
                Text('Trade name: $tradeName', style: theme.textTheme.bodySmall),
              if (status != 'active' && message != null) ...[
                const SizedBox(height: 6),
                Text(message, style: theme.textTheme.bodySmall),
              ],
              if (check['checkedAt'] != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Checked ${formatDateTime(check['checkedAt'])}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ImagePanel extends StatelessWidget {
  const _ImagePanel({
    required this.url,
    required this.onOpen,
    required this.onRetry,
  });
  final String? url;
  final VoidCallback? onOpen;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      height: 360,
      child: url == null
          ? const EmptyPanel(
              icon: Icons.image_not_supported_outlined,
              title: 'No image available',
              message: 'This invoice has no stored image.',
            )
          : InkWell(
              onTap: onOpen,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: url!,
                    cacheKey: ServerConfig.mediaCacheKey(url!),
                    fit: BoxFit.contain,
                    memCacheWidth: 1200,
                    placeholder: (_, _) =>
                        const Center(child: CircularProgressIndicator()),
                    errorWidget: (_, _, _) => _ImageError(onRetry: onRetry),
                  ),
                  const Positioned(
                    right: 12,
                    bottom: 12,
                    child: GlassPill(
                      label: 'Tap to zoom',
                      color: Brand.primary,
                      icon: Icons.zoom_in,
                    ),
                  ),
                ],
              ),
            ),
    ),
  );
}

/// Signed image links expire; reloading the invoice issues fresh ones.
class _ImageError extends StatelessWidget {
  const _ImageError({required this.onRetry, this.light = false});
  final VoidCallback onRetry;
  final bool light;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.broken_image_outlined,
          size: 48,
          color: light ? Colors.white70 : null,
        ),
        const SizedBox(height: 8),
        Text(
          'The image could not be loaded.\nThe link may have expired.',
          textAlign: TextAlign.center,
          style: TextStyle(color: light ? Colors.white70 : null),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Reload image'),
        ),
      ],
    ),
  );
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.url, required this.onRetry});
  final String url;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: const Text('Invoice image'),
    ),
    body: InteractiveViewer(
      minScale: 1,
      maxScale: 6,
      child: Center(
        child: CachedNetworkImage(
          imageUrl: url,
          cacheKey: ServerConfig.mediaCacheKey(url),
          fit: BoxFit.contain,
          placeholder: (_, _) => const CircularProgressIndicator(),
          errorWidget: (context, _, _) => _ImageError(
            light: true,
            onRetry: () {
              onRetry();
              Navigator.pop(context);
            },
          ),
        ),
      ),
    ),
  );
}

class _HistoryEntry extends StatelessWidget {
  const _HistoryEntry({required this.entry, required this.last});
  final Map<String, dynamic> entry;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = entry['action']?.toString() ?? 'updated';
    final color = switch (action) {
      'approved' => Brand.success,
      'rejected' => Brand.danger,
      'returned' => Brand.orange,
      'edited' => Brand.violet,
      _ => Brand.primary,
    };
    final by = entry['byName']?.toString();
    final remarks = entry['remarks']?.toString();
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                const SizedBox(height: 4),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(width: 2, color: theme.dividerColor),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    by == null || by.isEmpty
                        ? fieldLabel(action)
                        : '${fieldLabel(action)} by $by',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    formatDateTime(entry['at']),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (remarks != null && remarks.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(remarks),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable({required this.ocr, required this.edited});
  final Map<String, dynamic> ocr;
  final Map<String, dynamic> edited;
  @override
  Widget build(BuildContext context) {
    final keys = {
      ...ocr.keys,
      ...edited.keys,
    }.where((k) => ocr[k] is! Map && ocr[k] is! List).toList();
    if (keys.isEmpty) {
      return const EmptyPanel(
        icon: Icons.text_snippet_outlined,
        title: 'No extracted fields',
        message: 'Nothing was captured from this invoice.',
      );
    }
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(2),
      },
      border: TableBorder.all(color: Theme.of(context).dividerColor),
      children: [
        const TableRow(
          children: [
            _Cell('Field', header: true),
            _Cell('Captured', header: true),
            _Cell('Corrected', header: true),
          ],
        ),
        for (final key in keys)
          TableRow(
            children: [
              _Cell(fieldLabel(key)),
              _Cell('${ocr[key] ?? '—'}'),
              _Cell('${edited[key] ?? '—'}'),
            ],
          ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.text, {this.header = false});
  final String text;
  final bool header;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(10),
    child: Text(
      text,
      style: header ? const TextStyle(fontWeight: FontWeight.w700) : null,
    ),
  );
}

const _textFields = [
  ('vendorName', 'Vendor name'),
  ('gstin', 'Vendor GSTIN'),
  ('invoiceNumber', 'Invoice number'),
  ('invoiceDate', 'Invoice date (YYYY-MM-DD)'),
];
const _amountFields = [
  ('taxableValue', 'Taxable value'),
  ('cgst', 'CGST'),
  ('sgst', 'SGST'),
  ('igst', 'IGST'),
  ('discount', 'Discount'),
  ('netAmount', 'Invoice value'),
];

class _EditInvoiceSheet extends ConsumerStatefulWidget {
  const _EditInvoiceSheet({required this.invoiceId, required this.item});
  final String invoiceId;
  final Map<String, dynamic> item;
  @override
  ConsumerState<_EditInvoiceSheet> createState() => _EditInvoiceSheetState();
}

class _EditInvoiceSheetState extends ConsumerState<_EditInvoiceSheet> {
  final _form = GlobalKey<FormState>();
  late final Map<String, dynamic> _initial;
  late final Map<String, TextEditingController> _controllers;
  late final String? _initialCategory = widget.item['categoryId']?.toString();
  late String? _categoryId = _initialCategory;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final fields = invoiceFields(widget.item);
    _initial = {
      for (final (key, _) in [..._textFields, ..._amountFields])
        key: widget.item[key] ?? fields[key],
    };
    _controllers = {
      for (final entry in _initial.entries)
        entry.key: TextEditingController(
          text: entry.value == null ? '' : '${entry.value}',
        ),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final changes = <String, dynamic>{};
    for (final (key, _) in _textFields) {
      var text = _controllers[key]!.text.trim();
      if (key == 'gstin') text = normalizeGstin(text);
      if (text != '${_initial[key] ?? ''}') {
        changes[key] = text.isEmpty ? null : text;
      }
    }
    for (final (key, _) in _amountFields) {
      final text = _controllers[key]!.text.trim().replaceAll(',', '');
      final value = text.isEmpty ? null : num.parse(text);
      if (value != asNum(_initial[key])) changes[key] = value;
    }
    final categoryChanged = _categoryId != _initialCategory;
    if (changes.isEmpty && !categoryChanged) {
      Navigator.pop(context, false);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(invoiceRepositoryProvider)
          .update(
            widget.invoiceId,
            editedData: changes,
            setCategory: categoryChanged,
            categoryId: _categoryId,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        showSnack(context, apiError(error));
        setState(() => _saving = false);
      }
    }
  }

  String? _validate(String key, String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    if (key == 'gstin') return gstinError(text);
    if (key == 'invoiceDate' &&
        (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
            DateTime.tryParse(text) == null)) {
      return 'Use YYYY-MM-DD';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(invoiceCategoriesProvider);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Edit invoice fields',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Corrections are saved over the captured values and '
                  'recorded in the history.',
                ),
                const SizedBox(height: 16),
                for (final (key, label) in _textFields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      controller: _controllers[key],
                      textCapitalization: key == 'gstin'
                          ? TextCapitalization.characters
                          : TextCapitalization.none,
                      keyboardType: key == 'invoiceDate'
                          ? TextInputType.datetime
                          : TextInputType.text,
                      decoration: InputDecoration(labelText: label),
                      validator: (v) => _validate(key, v),
                    ),
                  ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final (key, label) in _amountFields)
                      SizedBox(
                        width: 160,
                        child: TextFormField(
                          controller: _controllers[key],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: label,
                            prefixText: '₹ ',
                          ),
                          validator: (v) {
                            final text = (v ?? '').trim().replaceAll(',', '');
                            return text.isEmpty || num.tryParse(text) != null
                                ? null
                                : 'Not a number';
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                categories.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) =>
                      Text('Categories unavailable: ${apiError(error)}'),
                  data: (items) {
                    final options = [
                      for (final c in items)
                        if (c['isActive'] != false || c['id'] == _categoryId) c,
                    ];
                    final known = options.any((c) => c['id'] == _categoryId);
                    return DropdownButtonFormField<String?>(
                      initialValue: known ? _categoryId : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('No category'),
                        ),
                        for (final c in options)
                          DropdownMenuItem(
                            value: c['id'].toString(),
                            child: Text(
                              c['name']?.toString() ?? '—',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _categoryId = v),
                    );
                  },
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving…' : 'Save changes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
