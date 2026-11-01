import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/format.dart';
import '../../core/glass.dart';
import '../../shared/widgets.dart';
import '../invoices/invoice_repository.dart';

final dashboardProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  final response = await ref.watch(dioProvider).get(ApiPaths.dashboard);
  return Map<String, dynamic>.from(response.data as Map);
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  void _openInvoices(BuildContext context, WidgetRef ref, String status) {
    ref
        .read(invoiceFiltersProvider.notifier)
        .set(InvoiceFilters(status: status));
    context.go('/invoices');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardProvider);
    return ContentPage(
      onRefresh: () => ref.refresh(dashboardProvider.future),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(
            title: 'Dashboard',
            subtitle: 'A live view of invoice activity and review workload.',
          ),
          const SizedBox(height: 28),
          state.when(
            skipLoadingOnRefresh: true,
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => ErrorPanel(
              message: apiError(error),
              onRetry: () => ref.invalidate(dashboardProvider),
            ),
            data: (data) => _content(context, ref, data),
          ),
        ],
      ),
    );
  }

  Widget _content(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> data,
  ) {
    final metrics = [
      (
        'Pending review',
        data['pendingCount'],
        Icons.pending_actions_rounded,
        Brand.warning,
        'pending',
      ),
      (
        "Today's uploads",
        data['todayUploads'],
        Icons.upload_file_rounded,
        Brand.primary,
        'all',
      ),
      (
        'Approved',
        data['approvedCount'],
        Icons.check_circle_rounded,
        Brand.success,
        'approved',
      ),
      (
        'Returned',
        data['returnedCount'],
        Icons.undo_rounded,
        Brand.orange,
        'returned',
      ),
      (
        'Rejected',
        data['rejectedCount'],
        Icons.cancel_rounded,
        Brand.danger,
        'rejected',
      ),
    ];
    final seats = data['seats'] is Map ? data['seats'] as Map : null;
    final daily = data['daily'] is List
        ? (data['daily'] as List).whereType<Map>().toList()
        : const <Map>[];
    final categories = data['topCategories'] is List
        ? (data['topCategories'] as List).whereType<Map>().toList()
        : const <Map>[];
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 650;
        final columns = narrow ? 2 : 5;
        final gap = narrow ? 12.0 : 16.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final m in metrics)
                  SizedBox(
                    width: width,
                    child: GlassCard(
                      padding: const EdgeInsets.all(18),
                      onTap: () => _openInvoices(context, ref, m.$5),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              IconBadge(icon: m.$3, color: m.$4),
                              const Spacer(),
                              Icon(Icons.chevron_right, color: muted),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '${m.$2 ?? 0}',
                            style: Theme.of(context).textTheme.displaySmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            m.$1,
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(color: muted),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: gap),
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                SizedBox(
                  width: narrow
                      ? constraints.maxWidth
                      : (constraints.maxWidth - gap) / 2,
                  child: GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AmountRow(
                          label: 'Approved value',
                          value: formatInr(data['approvedAmount'], whole: true),
                          color: Brand.success,
                        ),
                        const SizedBox(height: 12),
                        _AmountRow(
                          label: 'Awaiting review',
                          value: formatInr(data['pendingAmount'], whole: true),
                          color: Brand.warning,
                        ),
                        if (seats != null) ...[
                          const Divider(height: 28),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => context.go('/employees'),
                            child: _SeatsBar(
                              used: asNum(seats['used'])?.toInt() ?? 0,
                              limit: asNum(seats['limit'])?.toInt(),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (daily.isNotEmpty)
                  SizedBox(
                    width: narrow
                        ? constraints.maxWidth
                        : (constraints.maxWidth - gap) / 2,
                    child: GlassCard(child: _DailyChart(daily: daily)),
                  ),
              ],
            ),
            if (categories.isNotEmpty) ...[
              SizedBox(height: gap),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Top categories',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    for (final c in categories)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text('${c['name'] ?? 'Uncategorised'}'),
                        subtitle: Text('${c['count'] ?? 0} invoices'),
                        trailing: Text(
                          formatInr(c['amount'], whole: true),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(label)),
      Text(value, style: Theme.of(context).textTheme.titleMedium),
    ],
  );
}

class _SeatsBar extends StatelessWidget {
  const _SeatsBar({required this.used, required this.limit});
  final int used;
  final int? limit;
  @override
  Widget build(BuildContext context) {
    final full = limit != null && used >= limit!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people_outline, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  limit == null
                      ? '$used active employees'
                      : '$used of $limit seats used',
                ),
              ),
              if (full) const GlassPill(label: 'Full', color: Brand.danger),
            ],
          ),
          if (limit != null && limit! > 0) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (used / limit!).clamp(0, 1).toDouble(),
                minHeight: 8,
                color: full ? Brand.danger : Brand.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Uploads per day for the last two weeks.
class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.daily});
  final List<Map> daily;
  @override
  Widget build(BuildContext context) {
    final counts = [for (final d in daily) asNum(d['count'])?.toInt() ?? 0];
    final peak = math.max(1, counts.fold<int>(0, math.max));
    final total = counts.fold<int>(0, (a, b) => a + b);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Uploads, last ${daily.length} days',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text('$total in total', style: TextStyle(color: muted)),
        const SizedBox(height: 16),
        SizedBox(
          height: 110,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < daily.length; i++)
                Expanded(
                  child: Tooltip(
                    message:
                        '${formatDate(daily[i]['date'])}: ${counts[i]} uploads, '
                        '${formatInr(daily[i]['amount'], whole: true)}',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Container(
                        height: math.max(4, 100 * counts[i] / peak),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: Brand.primary.withValues(
                            alpha: counts[i] == 0 ? 0.2 : 0.85,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(_short(daily.first['date']), style: TextStyle(color: muted)),
            const Spacer(),
            Text(_short(daily.last['date']), style: TextStyle(color: muted)),
          ],
        ),
      ],
    );
  }

  static String _short(dynamic value) {
    final parsed = DateTime.tryParse('$value');
    return parsed == null ? '' : DateFormat('d MMM').format(parsed);
  }
}
