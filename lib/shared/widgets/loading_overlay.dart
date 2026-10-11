import 'package:flutter/material.dart';

import 'package:gst_expense_scanner/core/theme/glass.dart';

/// Full-screen blocking loader with optional message.
class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({super.key, this.message, this.visible = true});

  final String? message;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return ColoredBox(
      color: Brand.ink.withValues(alpha: 0.25),
      child: Center(
        child: GlassCard(
          blur: true,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                height: 36,
                width: 36,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              if (message != null) ...[
                const SizedBox(height: 16),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
