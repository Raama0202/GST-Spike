import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/format.dart';
import '../../core/glass.dart';
import '../../shared/widgets.dart';

const _pageSize = 50;

/// (label, exact `action` filter or null for everything)
const _filters = [
  ('All', null),
  ('Approved', 'invoice.approved'),
  ('Rejected', 'invoice.rejected'),
  ('Returned', 'invoice.returned'),
  ('Edited', 'invoice.edited'),
  ('Bulk decisions', 'invoice.bulk_decision'),
  ('Employees added', 'employee.created'),
  ('Settings', 'settings.updated'),
];

/// Company audit trail: who changed what, newest first.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});
  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  final _items = <Map<String, dynamic>>[];
  int _total = 0;
  int _page = 0;
  int _generation = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _moreError;
  String? _action;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (more &&
        (_loading ||
            _loadingMore ||
            _moreError != null ||
            _items.length >= _total)) {
      return;
    }
    final generation = more ? _generation : ++_generation;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
        _moreError = null;
      }
    });
    final page = more ? _page + 1 : 1;
    try {
      final response = await ref
          .read(dioProvider)
          .get(
            ApiPaths.audit,
            queryParameters: {
              'page': page,
              'pageSize': _pageSize,
              'action': ?_action,
            },
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        if (!more) _items.clear();
        _items.addAll(itemList(response.data));
        _total = itemTotal(response.data);
        _page = page;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        if (more) {
          _moreError = apiError(error);
        } else {
          _error = apiError(error);
        }
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SliverPage(
    onRefresh: _load,
    onEndReached: () => _load(more: true),
    slivers: [
      const SliverToBoxAdapter(
        child: PageHeader(
          title: 'Activity log',
          subtitle: 'Decisions, edits and settings changes in your company.',
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
      SliverToBoxAdapter(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (label, action) in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _action == action,
                    showCheckmark: false,
                    onSelected: (_) {
                      _action = action;
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
      if (_loading)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(),
          ),
        ),
      if (_error != null && _items.isEmpty)
        SliverToBoxAdapter(
          child: Card(
            child: ErrorPanel(message: _error!, onRetry: _load),
          ),
        )
      else if (!_loading && _items.isEmpty)
        const SliverToBoxAdapter(
          child: Card(
            child: EmptyPanel(
              icon: Icons.history_rounded,
              title: 'No activity yet',
              message: 'Approvals, edits and settings changes appear here.',
            ),
          ),
        )
      else if (_items.isNotEmpty) ...[
        SliverCard(
          sliver: SliverList.separated(
            itemCount: _items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) => _ActivityTile(item: _items[index]),
          ),
        ),
        SliverToBoxAdapter(
          child: LoadMoreFooter(
            loading: _loadingMore,
            error: _moreError,
            onRetry: () {
              setState(() => _moreError = null);
              _load(more: true);
            },
          ),
        ),
      ],
    ],
  );
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.item});
  final Map<String, dynamic> item;

  static (IconData, Color) _style(String action) {
    if (action.endsWith('approved')) {
      return (Icons.check_rounded, Brand.success);
    }
    if (action.endsWith('rejected')) return (Icons.close_rounded, Brand.danger);
    if (action.endsWith('returned')) return (Icons.undo_rounded, Brand.orange);
    if (action.startsWith('invoice.')) {
      return (Icons.receipt_long_rounded, Brand.indigo);
    }
    if (action.startsWith('employee.')) {
      return (Icons.person_rounded, Brand.teal);
    }
    if (action.startsWith('settings.') || action.startsWith('company.')) {
      return (Icons.settings_rounded, Brand.violet);
    }
    return (Icons.history_rounded, Brand.primary);
  }

  @override
  Widget build(BuildContext context) {
    final action = item['action']?.toString() ?? '';
    final (icon, color) = _style(action);
    final summary = item['summary']?.toString();
    final actor = item['actorEmail']?.toString();
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: IconBadge(icon: icon, color: color, size: 36),
      title: Text(
        summary == null || summary.isEmpty ? fieldLabel(action) : summary,
      ),
      subtitle: Text(
        [
          if (actor != null && actor.isNotEmpty) actor,
          formatDateTime(item['createdAt']),
        ].join(' • '),
      ),
    );
  }
}
