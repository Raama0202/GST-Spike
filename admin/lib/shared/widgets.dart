import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/glass.dart';

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.action,
  });
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      ?action,
    ],
  );
}

double pageHorizontalPadding(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 600 ? 16 : 32;

class ContentPage extends StatelessWidget {
  const ContentPage({super.key, required this.child, this.onRefresh});
  final Widget child;

  /// Enables pull-to-refresh.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final scroll = SingleChildScrollView(
      physics: onRefresh == null ? null : const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: pageHorizontalPadding(context),
        vertical: 24,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: child,
        ),
      ),
    );
    return onRefresh == null
        ? scroll
        : RefreshIndicator(onRefresh: onRefresh!, child: scroll);
  }
}

/// Lazily built page for long lists, with pull-to-refresh and a callback as
/// the user nears the end (infinite scroll).
class SliverPage extends StatefulWidget {
  const SliverPage({
    super.key,
    required this.slivers,
    required this.onRefresh,
    this.onEndReached,
  });
  final List<Widget> slivers;
  final Future<void> Function() onRefresh;

  /// Called repeatedly while near the end; callers guard against duplicates.
  final VoidCallback? onEndReached;

  @override
  State<SliverPage> createState() => _SliverPageState();
}

class _SliverPageState extends State<SliverPage> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_checkEnd);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _checkEnd() {
    if (widget.onEndReached == null || !_controller.hasClients) return;
    if (_controller.position.extentAfter < 600) widget.onEndReached!();
  }

  @override
  Widget build(BuildContext context) {
    // A first page that doesn't fill the screen can't be scrolled to load more.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkEnd();
    });
    final base = pageHorizontalPadding(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.max(base, (constraints.maxWidth - 1280) / 2);
        return RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: CustomScrollView(
            controller: _controller,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(side, 24, side, 32),
                sliver: SliverMainAxisGroup(slivers: widget.slivers),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Glass card behind a sliver list. Rows should sit on a transparent
/// [Material] so ink splashes paint above the card.
class SliverCard extends StatelessWidget {
  const SliverCard({super.key, required this.sliver});
  final Widget sliver;
  @override
  Widget build(BuildContext context) => DecoratedSliver(
    decoration: glassDecoration(dark: isDarkTheme(context)),
    sliver: SliverPadding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      sliver: sliver,
    ),
  );
}

/// Footer for paged lists: spinner while loading, retry after a failure.
class LoadMoreFooter extends StatelessWidget {
  const LoadMoreFooter({
    super.key,
    required this.loading,
    required this.error,
    required this.onRetry,
  });
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(error!, textAlign: TextAlign.center),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Load more'),
            ),
          ],
        ),
      );
    }
    return const SizedBox(height: 8);
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const IconBadge(
            icon: Icons.cloud_off_rounded,
            color: Brand.danger,
            size: 56,
          ),
          const SizedBox(height: 14),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconBadge(icon: icon, color: Brand.violet, size: 60),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

Color statusColor(String status) => switch (status.toLowerCase()) {
  'approved' || 'active' => Brand.success,
  'rejected' || 'suspended' || 'inactive' => Brand.danger,
  'returned' => Brand.orange,
  _ => Brand.primary,
};

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) =>
      GlassPill(label: status, color: statusColor(status));
}

void showSnack(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: Brand.danger)
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ) ??
    false;

/// Asks for decision remarks. Returns null when cancelled, otherwise the
/// trimmed text (possibly empty when [required] is false).
Future<String?> promptRemarks(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required bool required,
  String? message,
}) => showDialog<String>(
  context: context,
  builder: (_) => _RemarksDialog(
    title: title,
    confirmLabel: confirmLabel,
    required: required,
    message: message,
  ),
);

class _RemarksDialog extends StatefulWidget {
  const _RemarksDialog({
    required this.title,
    required this.confirmLabel,
    required this.required,
    this.message,
  });
  final String title;
  final String confirmLabel;
  final bool required;
  final String? message;
  @override
  State<_RemarksDialog> createState() => _RemarksDialogState();
}

class _RemarksDialogState extends State<_RemarksDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (widget.required && text.isEmpty) {
      setState(() => _error = 'Tell the employee what to fix');
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message != null) ...[
            Text(widget.message!),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _controller,
            maxLines: 3,
            maxLength: 1000,
            autofocus: widget.required,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: widget.required
                  ? 'Remarks (required)'
                  : 'Remarks (optional)',
              hintText: 'Add context for the employee',
              errorText: _error,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
    ],
  );
}
