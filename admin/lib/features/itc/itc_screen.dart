import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/file_share.dart';
import '../../core/format.dart';
import '../../core/glass.dart';
import '../../shared/widgets.dart';

final _periodPattern = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');

String _defaultPeriod() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
}

const _statusLabels = {
  'matched': 'Matched',
  'missing_in_2b': 'Missing in 2B',
  'missing_in_books': 'Missing in books',
  'mismatch': 'Mismatch',
  'partial': 'Partial',
};

class _ItcData {
  const _ItcData({
    required this.apiConfigured,
    required this.counts,
    required this.matches,
    required this.reminders,
  });
  final bool apiConfigured;
  final Map<String, dynamic> counts;
  final List<Map<String, dynamic>> matches;
  final List<Map<String, dynamic>> reminders;
}

class ItcScreen extends ConsumerStatefulWidget {
  const ItcScreen({super.key});

  @override
  ConsumerState<ItcScreen> createState() => _ItcScreenState();
}

class _ItcScreenState extends ConsumerState<ItcScreen> {
  late final _periodField = TextEditingController(text: _defaultPeriod());
  late String _period = _periodField.text;
  String _returnType = '2B';
  String? _statusFilter;
  bool _busy = false;
  late Future<_ItcData> _future = _fetch();

  Dio get _dio => ref.read(dioProvider);

  @override
  void dispose() {
    _periodField.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _scope => {
    'period': _period,
    'returnType': _returnType,
  };

  Future<_ItcData> _fetch() async {
    final results = await Future.wait([
      _dio.get(ApiPaths.itcStatus),
      _dio.get(ApiPaths.itcSummary, queryParameters: _scope),
      _dio.get(
        ApiPaths.itcMatches,
        queryParameters: {..._scope, 'status': ?_statusFilter},
      ),
      _dio.get(
        ApiPaths.itcReminders,
        queryParameters: {'status': 'manual_followup'},
      ),
    ]);
    final portal = results[0].data is Map ? results[0].data as Map : const {};
    final summary = results[1].data is Map ? results[1].data as Map : const {};
    return _ItcData(
      apiConfigured: portal['portalApiConfigured'] == true,
      counts: Map<String, dynamic>.from(summary['counts'] as Map? ?? {}),
      matches: itemList(results[2].data),
      reminders: itemList(results[3].data),
    );
  }

  void _reload() => setState(() => _future = _fetch());

  Future<void> _refresh() async {
    _reload();
    try {
      await _future;
    } catch (_) {
      // Rendered by the FutureBuilder.
    }
  }

  void _toast(String message) {
    if (mounted) showSnack(context, message);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      _toast(apiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls', 'csv'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      _toast('Could not read the selected file');
      return;
    }
    await _run(() async {
      final form = FormData.fromMap({
        ..._scope,
        'file': MultipartFile.fromBytes(bytes, filename: file.name),
      });
      final response = await _dio.post(ApiPaths.itcImport, data: form);
      final data = response.data is Map ? response.data as Map : const {};
      final rowCount = data['rowCount'] ?? 0;
      _toast(
        data['status'] == 'processing'
            ? '$rowCount rows are being processed. Pull to refresh in a minute.'
            : 'Imported $rowCount rows and rebuilt matches',
      );
      _reload();
    });
  }

  Future<void> _reconcile() => _run(() async {
    await _dio.post(ApiPaths.itcReconcile, queryParameters: _scope);
    _toast('Matches rebuilt');
    _reload();
  });

  Future<void> _remindAll(List<Map<String, dynamic>> matches) async {
    var items = <Map<String, dynamic>>[];
    var skipped = 0;
    await _run(() async {
      final response = await _dio.post(
        ApiPaths.itcRemindMissing,
        queryParameters: _scope,
      );
      final data = response.data is Map ? response.data as Map : const {};
      items = itemList(data);
      skipped = (data['skipped'] as num?)?.toInt() ?? 0;
      _reload();
      if (items.isEmpty) {
        _toast(
          skipped > 0
              ? 'All $skipped suppliers already have an open reminder.'
              : 'No missing invoices need a reminder.',
        );
      }
    });
    if (items.isNotEmpty && mounted) {
      await _showReminders(items, matches, skipped: skipped);
    }
  }

  Future<void> _remindOne(
    Map<String, dynamic> match,
    List<Map<String, dynamic>> matches,
  ) async {
    Map<String, dynamic>? reminder;
    await _run(() async {
      final response = await _dio.post(
        '${ApiPaths.itcMatches}/${match['id']}/remind',
      );
      reminder = Map<String, dynamic>.from(response.data as Map);
      _reload();
    });
    if (reminder != null && mounted) {
      await _showReminders([reminder!], matches);
    }
  }

  Future<void> _showReminders(
    List<Map<String, dynamic>> reminders,
    List<Map<String, dynamic>> matches, {
    int skipped = 0,
  }) {
    final byMatch = {for (final m in matches) m['id']: m};
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReminderSheet(
        reminders: reminders,
        skipped: skipped,
        supplierOf: (reminder) {
          final match = byMatch[reminder['matchId']];
          return (match?['invoice']?['vendorName'] ??
                  match?['portalRow']?['supplierName'])
              ?.toString();
        },
      ),
    );
  }

  Future<void> _export() => _run(() async {
    final response = await _dio.get(
      ApiPaths.itcExport,
      queryParameters: {..._scope, 'status': _statusFilter ?? 'all'},
    );
    final data = response.data is Map ? response.data as Map : const {};
    final filename =
        data['filename']?.toString() ?? 'itc_${_period}_$_returnType.csv';
    if (!mounted) return;
    await shareFile(
      context,
      csvBytes(data['csv']?.toString() ?? ''),
      filename: filename,
      mimeType: csvMime,
    );
  });

  Future<void> _updateReminder(String id, Map<String, dynamic> change) =>
      _run(() async {
        await _dio.patch('${ApiPaths.itcReminders}/$id', data: change);
        _reload();
      });

  @override
  Widget build(BuildContext context) {
    return SliverPage(
      onRefresh: _refresh,
      slivers: [
        const SliverToBoxAdapter(
          child: PageHeader(
            title: 'ITC / GSTR-2A & 2B',
            subtitle:
                'Import portal downloads, match scanned bills, and chase missing ITC.',
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 150,
                child: TextField(
                  controller: _periodField,
                  keyboardType: TextInputType.datetime,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                    LengthLimitingTextInputFormatter(7),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Period',
                    hintText: 'YYYY-MM',
                  ),
                  onChanged: (value) {
                    if (_periodPattern.hasMatch(value) && value != _period) {
                      _period = value;
                      _reload();
                    }
                  },
                ),
              ),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<String>(
                  initialValue: _returnType,
                  decoration: const InputDecoration(labelText: 'Return'),
                  items: const [
                    DropdownMenuItem(value: '2B', child: Text('GSTR-2B')),
                    DropdownMenuItem(value: '2A', child: Text('GSTR-2A')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _returnType = value;
                    _reload();
                  },
                ),
              ),
              SizedBox(
                width: 210,
                child: DropdownButtonFormField<String?>(
                  // Count tiles also set the filter; re-key to show it.
                  key: ValueKey(_statusFilter),
                  initialValue: _statusFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All statuses'),
                    ),
                    for (final entry in _statusLabels.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (value) {
                    _statusFilter = value;
                    _reload();
                  },
                ),
              ),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _importFile,
                icon: const Icon(Icons.upload_file),
                label: const Text('Import Excel/CSV'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _reconcile,
                icon: const Icon(Icons.sync),
                label: const Text('Rebuild matches'),
              ),
              FutureBuilder<_ItcData>(
                future: _future,
                builder: (context, snapshot) => OutlinedButton.icon(
                  onPressed: _busy || !snapshot.hasData
                      ? null
                      : () => _remindAll(snapshot.data!.matches),
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Remind missing'),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _export,
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Export CSV'),
              ),
            ],
          ),
        ),
        if (_busy)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        FutureBuilder<_ItcData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SliverToBoxAdapter(child: LinearProgressIndicator());
            }
            if (snapshot.hasError) {
              return SliverToBoxAdapter(
                child: Card(
                  child: ErrorPanel(
                    message: apiError(snapshot.error!),
                    onRetry: _reload,
                  ),
                ),
              );
            }
            return _results(context, snapshot.data!);
          },
        ),
      ],
    );
  }

  Widget _results(BuildContext context, _ItcData data) {
    final titleStyle = Theme.of(context).textTheme.titleLarge;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Card(
            child: ListTile(
              leading: Icon(
                data.apiConfigured ? Icons.cloud_done : Icons.cloud_off,
                color: data.apiConfigured ? Brand.success : Brand.warning,
              ),
              title: Text(
                data.apiConfigured
                    ? 'GSP portal API configured'
                    : 'Excel upload mode (no GSP API keys)',
              ),
              subtitle: const Text(
                'Official GSTN access needs a paid GSP. Upload 2A/2B Excel from gst.gov.in for free.',
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 600 ? 2 : 4;
              final width =
                  (constraints.maxWidth - 12 * (columns - 1)) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final (key, icon, color) in const [
                    ('matched', Icons.check_circle, Brand.success),
                    ('missing_in_2b', Icons.warning_amber, Brand.warning),
                    ('missing_in_books', Icons.receipt_long, Brand.primary),
                    ('mismatch', Icons.compare_arrows, Brand.danger),
                  ])
                    SizedBox(
                      width: width,
                      child: GlassCard(
                        padding: const EdgeInsets.all(16),
                        onTap: () {
                          setState(() => _statusFilter = key);
                          _reload();
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(icon, color: color),
                            const SizedBox(height: 8),
                            Text(
                              '${data.counts[key] ?? 0}',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            Text(_statusLabels[key]!),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
        SliverToBoxAdapter(
          child: Text('Matches (${data.matches.length})', style: titleStyle),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        if (data.matches.isEmpty)
          const SliverToBoxAdapter(
            child: Card(
              child: EmptyPanel(
                icon: Icons.compare_arrows_outlined,
                title: 'No matches yet',
                message: 'Import a 2A/2B file for this period.',
              ),
            ),
          )
        else
          SliverCard(
            sliver: SliverList.separated(
              itemCount: data.matches.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = data.matches[index];
                final invoice = item['invoice'] is Map
                    ? item['invoice'] as Map
                    : null;
                final portal = item['portalRow'] is Map
                    ? item['portalRow'] as Map
                    : null;
                final status = item['status']?.toString() ?? '';
                final remindable =
                    invoice != null &&
                    (status == 'missing_in_2b' || status == 'mismatch');
                return Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    title: Text(
                      (invoice?['vendorName'] ??
                              portal?['supplierName'] ??
                              'Unknown supplier')
                          .toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        _statusLabels[status] ?? status,
                        invoice?['invoiceNumber'] ?? portal?['invoiceNumber'],
                        if ((invoice?['netAmount'] ?? portal?['netAmount']) !=
                            null)
                          formatInr(
                            invoice?['netAmount'] ?? portal?['netAmount'],
                          ),
                        item['notes'],
                      ].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
                    ),
                    trailing: remindable
                        ? TextButton(
                            onPressed: _busy
                                ? null
                                : () => _remindOne(item, data.matches),
                            child: const Text('Remind'),
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
        SliverToBoxAdapter(
          child: Text('Manual follow-up queue', style: titleStyle),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Text(
              'Bills without WhatsApp/email contacts land here for the owner to call.',
              style: TextStyle(color: muted),
            ),
          ),
        ),
        if (data.reminders.isEmpty)
          const SliverToBoxAdapter(child: Text('No manual follow-ups pending.'))
        else
          SliverCard(
            sliver: SliverList.separated(
              itemCount: data.reminders.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = data.reminders[index];
                final id = item['id'].toString();
                return Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    title: Text(
                      item['messagePreview']?.toString() ?? 'Follow up',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        if (item['contactPhone'] != null)
                          'Phone: ${item['contactPhone']}',
                        if (item['contactEmail'] != null)
                          'Email: ${item['contactEmail']}',
                        if (item['called'] == true) 'Called',
                      ].join(' · '),
                    ),
                    trailing: PopupMenuButton<String>(
                      enabled: !_busy,
                      onSelected: (action) => _updateReminder(
                        id,
                        action == 'called'
                            ? {'called': true}
                            : {'resolved': true},
                      ),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'called',
                          child: Text('Mark called'),
                        ),
                        PopupMenuItem(
                          value: 'resolved',
                          child: Text('Mark resolved'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// One row per supplier with its own send buttons, so the admin decides what
/// to open instead of the app launching a burst of WhatsApp links.
class _ReminderSheet extends StatelessWidget {
  const _ReminderSheet({
    required this.reminders,
    required this.skipped,
    required this.supplierOf,
  });
  final List<Map<String, dynamic>> reminders;
  final int skipped;
  final String? Function(Map<String, dynamic> reminder) supplierOf;

  Future<void> _open(BuildContext context, String? url) async {
    if (url == null || url.isEmpty) return;
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      showSnack(context, 'No app is available to open this link.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reminders.length == 1
                        ? 'Reminder ready'
                        : '${reminders.length} reminders ready',
                    style: theme.textTheme.titleLarge,
                  ),
                  Text(
                    [
                      'Send each one from WhatsApp or email.',
                      if (skipped > 0) '$skipped already had an open reminder.',
                    ].join(' '),
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: reminders.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final r = reminders[index];
                  final wa = r['whatsappUrl']?.toString();
                  final mail = r['mailtoUrl']?.toString();
                  final message = r['message']?.toString() ?? '';
                  final contact = [
                    r['contactPhone'],
                    r['contactEmail'],
                  ].where((e) => e != null && '$e'.isNotEmpty).join(' · ');
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          supplierOf(r) ?? 'Supplier',
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          contact.isEmpty
                              ? 'No phone or email on the bill'
                              : contact,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          message,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (wa != null && wa.isNotEmpty)
                              FilledButton.tonalIcon(
                                onPressed: () => _open(context, wa),
                                icon: const Icon(Icons.chat_outlined),
                                label: const Text('WhatsApp'),
                              ),
                            if (mail != null && mail.isNotEmpty)
                              OutlinedButton.icon(
                                onPressed: () => _open(context, mail),
                                icon: const Icon(Icons.mail_outline),
                                label: const Text('Email'),
                              ),
                            if (message.isNotEmpty)
                              OutlinedButton.icon(
                                onPressed: () => SharePlus.instance.share(
                                  ShareParams(text: message),
                                ),
                                icon: const Icon(Icons.share_outlined),
                                label: const Text('Share'),
                              ),
                            if (r['status'] == 'manual_followup')
                              const GlassPill(
                                label: 'Added to manual follow-up',
                                color: Brand.orange,
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
