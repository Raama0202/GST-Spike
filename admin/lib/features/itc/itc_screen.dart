import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../shared/widgets.dart';

String _defaultPeriod() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
}

class ItcScreen extends ConsumerStatefulWidget {
  const ItcScreen({super.key});

  @override
  ConsumerState<ItcScreen> createState() => _ItcScreenState();
}

class _ItcScreenState extends ConsumerState<ItcScreen> {
  bool _busy = false;
  late String _period = _defaultPeriod();
  String _returnType = '2B';
  String? _statusFilter;
  int _reloadToken = 0;

  Future<Map<String, dynamic>> _loadSummary() async {
    final response = await ref.read(dioProvider).get(
      ApiPaths.itcSummary,
      queryParameters: {'period': _period, 'returnType': _returnType},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> _loadMatches() async {
    final response = await ref.read(dioProvider).get(
      ApiPaths.itcMatches,
      queryParameters: {
        'period': _period,
        'returnType': _returnType,
        if (_statusFilter != null) 'status': _statusFilter,
      },
    );
    return itemList(response.data);
  }

  Future<List<Map<String, dynamic>>> _loadReminders() async {
    final response = await ref.read(dioProvider).get(
      ApiPaths.itcReminders,
      queryParameters: {'status': 'manual_followup'},
    );
    return itemList(response.data);
  }

  Future<Map<String, dynamic>> _loadPortalStatus() async {
    final response = await ref.read(dioProvider).get(ApiPaths.itcStatus);
    return Map<String, dynamic>.from(response.data as Map);
  }

  void _refresh() => setState(() => _reloadToken++);

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
      _toast('Could not read file bytes');
      return;
    }

    setState(() => _busy = true);
    try {
      final form = FormData.fromMap({
        'period': _period,
        'returnType': _returnType,
        'file': MultipartFile.fromBytes(bytes, filename: file.name),
      });
      final response =
          await ref.read(dioProvider).post(ApiPaths.itcImport, data: form);
      final rowCount = response.data['rowCount'] ?? 0;
      _toast(
        response.data['status'] == 'processing'
            ? '$rowCount rows are being processed. Refresh in a minute to see matches.'
            : 'Imported $rowCount rows and rebuilt matches',
      );
      _refresh();
    } catch (error) {
      _toast(apiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reconcile() async {
    setState(() => _busy = true);
    try {
      await ref.read(dioProvider).post(
        ApiPaths.itcReconcile,
        queryParameters: {'period': _period, 'returnType': _returnType},
      );
      _toast('Matches rebuilt');
      _refresh();
    } catch (error) {
      _toast(apiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remindAll() async {
    setState(() => _busy = true);
    try {
      final response = await ref.read(dioProvider).post(
        ApiPaths.itcRemindMissing,
        queryParameters: {'period': _period, 'returnType': _returnType},
      );
      final count = response.data['count'] ?? 0;
      _toast('Prepared $count reminders');
      final items = itemList(response.data);
      if (items.isNotEmpty) await _openReminderLinks(items);
      _refresh();
    } catch (error) {
      _toast(apiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remindOne(String matchId) async {
    setState(() => _busy = true);
    try {
      final response = await ref
          .read(dioProvider)
          .post('${ApiPaths.itcMatches}/$matchId/remind');
      final data = Map<String, dynamic>.from(response.data as Map);
      await _openReminderLinks([data]);
      _refresh();
    } catch (error) {
      _toast(apiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openReminderLinks(List<Map<String, dynamic>> items) async {
    for (final item in items) {
      final wa = item['whatsappUrl']?.toString();
      final mail = item['mailtoUrl']?.toString();
      final status = item['status']?.toString();
      if (wa != null && wa.isNotEmpty) {
        final uri = Uri.parse(wa);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } else if (mail != null && mail.isNotEmpty) {
        final uri = Uri.parse(mail);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
      } else if (status == 'manual_followup') {
        _toast('No phone/email on bill — added to manual follow-up');
      }
    }
  }

  Future<void> _copyExport() async {
    try {
      final response = await ref.read(dioProvider).get(
        ApiPaths.itcExport,
        queryParameters: {
          'period': _period,
          'returnType': _returnType,
          'status': _statusFilter ?? 'missing_in_2b',
        },
      );
      final csv = response.data['csv']?.toString() ?? '';
      await Clipboard.setData(ClipboardData(text: csv));
      _toast('CSV copied to clipboard');
    } catch (error) {
      _toast(apiError(error));
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ContentPage(
      child: FutureBuilder(
        key: ValueKey('$_reloadToken-$_period-$_returnType-$_statusFilter'),
        future: Future.wait([
          _loadPortalStatus(),
          _loadSummary(),
          _loadMatches(),
          _loadReminders(),
        ]),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeader(
                  title: 'ITC / GSTR-2A & 2B',
                  subtitle: 'Loading…',
                ),
                SizedBox(height: 24),
                LinearProgressIndicator(),
              ],
            );
          }
          if (snapshot.hasError) {
            return ErrorPanel(
              message: apiError(snapshot.error!),
              onRetry: _refresh,
            );
          }
          final portal = snapshot.data![0] as Map<String, dynamic>;
          final summary = snapshot.data![1] as Map<String, dynamic>;
          final matches = snapshot.data![2] as List<Map<String, dynamic>>;
          final reminders = snapshot.data![3] as List<Map<String, dynamic>>;
          final counts =
              Map<String, dynamic>.from(summary['counts'] as Map? ?? {});
          final apiOn = portal['portalApiConfigured'] == true;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: 'ITC / GSTR-2A & 2B',
                subtitle:
                    'Import portal downloads, match scanned bills, and chase missing ITC.',
                action: Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _importFile,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Import Excel/CSV'),
                    ),
                    OutlinedButton(
                      onPressed: _busy ? null : _reconcile,
                      child: const Text('Rebuild matches'),
                    ),
                    OutlinedButton(
                      onPressed: _busy ? null : _remindAll,
                      child: const Text('Remind missing'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _copyExport,
                      child: const Text('Copy CSV'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: Icon(
                    apiOn ? Icons.cloud_done : Icons.cloud_off,
                    color: apiOn ? Colors.green : Colors.orange,
                  ),
                  title: Text(
                    apiOn
                        ? 'GSP portal API configured'
                        : 'Excel upload mode (no GSP API keys)',
                  ),
                  subtitle: const Text(
                    'Official GSTN access needs a paid GSP. Upload 2A/2B Excel from gst.gov.in for free.',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  SizedBox(
                    width: 140,
                    child: TextFormField(
                      initialValue: _period,
                      decoration:
                          const InputDecoration(labelText: 'Period YYYY-MM'),
                      onChanged: (value) {
                        if (RegExp(r'^\d{4}-\d{2}$').hasMatch(value)) {
                          setState(() => _period = value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  DropdownButton<String>(
                    value: _returnType,
                    items: const [
                      DropdownMenuItem(value: '2B', child: Text('GSTR-2B')),
                      DropdownMenuItem(value: '2A', child: Text('GSTR-2A')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _returnType = value);
                    },
                  ),
                  const SizedBox(width: 16),
                  DropdownButton<String?>(
                    value: _statusFilter,
                    hint: const Text('All statuses'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('All statuses')),
                      DropdownMenuItem(value: 'matched', child: Text('Matched')),
                      DropdownMenuItem(
                        value: 'missing_in_2b',
                        child: Text('Missing in 2B'),
                      ),
                      DropdownMenuItem(
                        value: 'missing_in_books',
                        child: Text('Missing in books'),
                      ),
                      DropdownMenuItem(
                        value: 'mismatch',
                        child: Text('Mismatch'),
                      ),
                      DropdownMenuItem(value: 'partial', child: Text('Partial')),
                    ],
                    onChanged: (value) => setState(() => _statusFilter = value),
                  ),
                ],
              ),
              if (_busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in [
                    ('Matched', counts['matched'] ?? 0, Icons.check_circle),
                    (
                      'Missing in 2B',
                      counts['missing_in_2b'] ?? 0,
                      Icons.warning_amber,
                    ),
                    (
                      'Missing in books',
                      counts['missing_in_books'] ?? 0,
                      Icons.receipt_long,
                    ),
                    ('Mismatch', counts['mismatch'] ?? 0, Icons.compare_arrows),
                  ])
                    SizedBox(
                      width: 180,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(c.$3, color: const Color(0xFF0B5FFF)),
                              const SizedBox(height: 8),
                              Text(
                                '${c.$2}',
                                style:
                                    Theme.of(context).textTheme.headlineMedium,
                              ),
                              Text(c.$1),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 28),
              Text('Matches', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (matches.isEmpty)
                const Text(
                  'No matches yet. Import a 2A/2B file for this period.',
                )
              else
                for (final item in matches)
                  Card(
                    child: ListTile(
                      title: Text(
                        (item['invoice']?['vendorName'] ??
                                item['portalRow']?['supplierName'] ??
                                'Unknown supplier')
                            .toString(),
                      ),
                      subtitle: Text(
                        [
                          item['status'],
                          item['invoice']?['invoiceNumber'] ??
                              item['portalRow']?['invoiceNumber'],
                          item['notes'],
                        ]
                            .where((e) => e != null && '$e'.isNotEmpty)
                            .join(' · '),
                      ),
                      trailing: item['invoice'] != null &&
                              (item['status'] == 'missing_in_2b' ||
                                  item['status'] == 'mismatch')
                          ? TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _remindOne(item['id'].toString()),
                              child: const Text('Remind'),
                            )
                          : null,
                    ),
                  ),
              const SizedBox(height: 28),
              Text(
                'Manual follow-up queue',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Bills without WhatsApp/email contacts land here for the owner to call.',
              ),
              const SizedBox(height: 12),
              if (reminders.isEmpty)
                const Text('No manual follow-ups pending.')
              else
                for (final item in reminders)
                  Card(
                    child: ListTile(
                      title: Text(
                        item['messagePreview']?.toString() ?? 'Follow up',
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
                      trailing: Wrap(
                        children: [
                          TextButton(
                            onPressed: () async {
                              await ref.read(dioProvider).patch(
                                '${ApiPaths.itcReminders}/${item['id']}',
                                data: {'called': true},
                              );
                              _refresh();
                            },
                            child: const Text('Mark called'),
                          ),
                          TextButton(
                            onPressed: () async {
                              await ref.read(dioProvider).patch(
                                '${ApiPaths.itcReminders}/${item['id']}',
                                data: {'resolved': true},
                              );
                              _refresh();
                            },
                            child: const Text('Resolved'),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
