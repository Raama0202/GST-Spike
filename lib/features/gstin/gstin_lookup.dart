import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gst_expense_scanner/core/di/providers.dart';
import 'package:gst_expense_scanner/core/errors/exceptions.dart';
import 'package:gst_expense_scanner/core/theme/glass.dart';

/// Result of `GET /gstin/{gstin}`: the taxpayer's status on the GST portal.
class GstinLookup {
  const GstinLookup({
    required this.gstin,
    required this.status,
    required this.liveCheck,
    this.legalName,
    this.tradeName,
    this.stateName,
    this.message,
  });

  factory GstinLookup.fromJson(Map<String, dynamic> json) => GstinLookup(
        gstin: json['gstin'] as String? ?? '',
        status: json['status'] as String? ?? 'unverified',
        liveCheck: json['liveCheck'] as bool? ?? false,
        legalName: json['legalName'] as String?,
        tradeName: json['tradeName'] as String?,
        stateName: json['stateName'] as String?,
        message: json['message'] as String?,
      );

  final String gstin;
  final String status;
  final bool liveCheck;
  final String? legalName;
  final String? tradeName;
  final String? stateName;
  final String? message;

  bool get isActive => status == 'active';
  bool get isProblem => const {
        'cancelled',
        'suspended',
        'inactive',
        'not_found',
        'invalid_format',
      }.contains(status);

  String get label => switch (status) {
        'active' => 'Active on GST portal',
        'cancelled' => 'GSTIN cancelled',
        'suspended' => 'GSTIN suspended',
        'inactive' => 'GSTIN inactive',
        'not_found' => 'Not found on GST portal',
        'invalid_format' => 'Invalid GSTIN',
        _ => 'Not verified',
      };
}

Future<GstinLookup> lookupGstin(WidgetRef ref, String gstin) async {
  final response = await ref
      .read(apiClientProvider)
      .get<Map<String, dynamic>>('/gstin/${Uri.encodeComponent(gstin)}');
  return GstinLookup.fromJson(response.data ?? const {});
}

/// "Verify with GST portal" under a GSTIN field on the review screen.
class GstinVerifyPanel extends ConsumerStatefulWidget {
  const GstinVerifyPanel({
    super.key,
    required this.gstin,
    required this.vendorName,
    required this.onUseName,
  });

  /// Upper-cased, format-valid GSTIN currently in the field.
  final String gstin;
  final String vendorName;
  final ValueChanged<String> onUseName;

  @override
  ConsumerState<GstinVerifyPanel> createState() => _GstinVerifyPanelState();
}

class _GstinVerifyPanelState extends ConsumerState<GstinVerifyPanel> {
  GstinLookup? _result;
  String? _error;
  bool _busy = false;

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await lookupGstin(ref, widget.gstin);
      if (!mounted) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is AppException
            ? error.failure.message
            : 'Could not reach the GST portal',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result?.gstin == widget.gstin ? _result : null;

    if (result == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            TextButton.icon(
              onPressed: _busy ? null : _verify,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_user_outlined, size: 18),
              label: Text(_busy ? 'Checking…' : 'Verify with GST portal'),
            ),
            if (_error != null)
              Expanded(
                child: Text(
                  _error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Brand.danger),
                ),
              ),
          ],
        ),
      );
    }

    final color = result.isActive
        ? Brand.success
        : result.isProblem
            ? Brand.danger
            : Brand.warning;
    final name = result.legalName ?? result.tradeName;
    final differs = name != null &&
        name.trim().toLowerCase() != widget.vendorName.trim().toLowerCase();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        tint: color,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.isActive
                      ? Icons.verified_rounded
                      : result.isProblem
                          ? Icons.gpp_bad_rounded
                          : Icons.help_outline_rounded,
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.label,
                    style: theme.textTheme.titleSmall?.copyWith(color: color),
                  ),
                ),
              ],
            ),
            if (result.liveCheck && name != null) ...[
              const SizedBox(height: 6),
              Text(name, style: theme.textTheme.bodyMedium),
              if (result.tradeName != null && result.tradeName != name)
                Text(
                  'Trade name: ${result.tradeName}',
                  style: theme.textTheme.bodySmall,
                ),
              if (result.stateName != null)
                Text(result.stateName!, style: theme.textTheme.bodySmall),
            ],
            if (!result.isActive && result.message != null) ...[
              const SizedBox(height: 6),
              Text(result.message!, style: theme.textTheme.bodySmall),
            ],
            if (result.isProblem) ...[
              const SizedBox(height: 6),
              Text(
                'Input tax credit may not be available on this bill. '
                'Check the GSTIN with the supplier.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (result.liveCheck && differs)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => widget.onUseName(name),
                  child: const Text('Use as vendor name'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
