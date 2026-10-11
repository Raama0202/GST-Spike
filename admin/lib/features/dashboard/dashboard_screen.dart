import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/glass.dart';
import '../../shared/widgets.dart';

final dashboardProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  final response = await ref.watch(dioProvider).get(ApiPaths.dashboard);
  return Map<String, dynamic>.from(response.data as Map);
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardProvider);
    return ContentPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(
            title: 'Dashboard',
            subtitle: 'A live view of invoice activity and review workload.',
          ),
          const SizedBox(height: 28),
          state.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => ErrorPanel(
              message: apiError(error),
              onRetry: () => ref.invalidate(dashboardProvider),
            ),
            data: (data) {
              final metrics = [
                (
                  'Pending review',
                  data['pendingCount'] ?? 0,
                  Icons.pending_actions_rounded,
                  Brand.warning,
                ),
                (
                  "Today's uploads",
                  data['todayUploads'] ?? 0,
                  Icons.upload_file_rounded,
                  Brand.primary,
                ),
                (
                  'Approved',
                  data['approvedCount'] ?? 0,
                  Icons.check_circle_rounded,
                  Brand.success,
                ),
                (
                  'Rejected',
                  data['rejectedCount'] ?? 0,
                  Icons.cancel_rounded,
                  Brand.danger,
                ),
              ];
              return LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth < 650
                      ? (constraints.maxWidth - 12) / 2
                      : (constraints.maxWidth - 48) / 4;
                  return Wrap(
                    spacing: constraints.maxWidth < 650 ? 12 : 16,
                    runSpacing: constraints.maxWidth < 650 ? 12 : 16,
                    children: metrics
                        .map(
                          (m) => SizedBox(
                            width: width,
                            child: GlassCard(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  IconBadge(icon: m.$3, color: m.$4),
                                  const SizedBox(height: 16),
                                  Text(
                                    '${m.$2}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.displaySmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    m.$1,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: Brand.muted),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
