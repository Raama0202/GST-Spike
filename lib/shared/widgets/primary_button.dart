import 'package:flutter/material.dart';

import 'package:gst_expense_scanner/core/theme/glass.dart';

/// Large gradient action button for one-hand use.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return GlassButton(
      label: label,
      onPressed: onPressed,
      icon: icon,
      loading: loading,
      expand: expand,
    );
  }
}
