import 'package:flutter/material.dart';

import 'package:gst_expense_scanner/core/theme/glass.dart';
import 'package:gst_expense_scanner/shared/models/invoice_entity.dart';

/// Compact status badge for sync and approval states.
class StatusChip extends StatelessWidget {
  const StatusChip.sync(this.status, {super.key}) : approvalStatus = null;

  const StatusChip.approval(this.approvalStatus, {super.key}) : status = null;

  final SyncStatus? status;
  final ApprovalStatus? approvalStatus;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = _resolve(context);
    return GlassPill(label: label, color: color, icon: icon);
  }

  (String, Color, IconData) _resolve(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (status != null) {
      return switch (status!) {
        SyncStatus.pending => (
          'Pending',
          Brand.warning,
          Icons.schedule_rounded,
        ),
        SyncStatus.uploading => (
          'Uploading',
          scheme.primary,
          Icons.cloud_upload_rounded,
        ),
        SyncStatus.uploaded => (
          'Uploaded',
          Brand.success,
          Icons.cloud_done_rounded,
        ),
        SyncStatus.failed => ('Failed', Brand.danger, Icons.error_rounded),
      };
    }
    return switch (approvalStatus!) {
      ApprovalStatus.pending => (
        'Review pending',
        Brand.muted,
        Icons.hourglass_top_rounded,
      ),
      ApprovalStatus.uploaded => (
        'Submitted',
        scheme.primary,
        Icons.send_rounded,
      ),
      ApprovalStatus.approved => (
        'Approved',
        Brand.success,
        Icons.check_circle_rounded,
      ),
      ApprovalStatus.rejected => (
        'Rejected',
        Brand.danger,
        Icons.cancel_rounded,
      ),
      ApprovalStatus.returned => ('Returned', Brand.orange, Icons.undo_rounded),
    };
  }
}
