import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:gst_expense_scanner/core/di/providers.dart';
import 'package:gst_expense_scanner/core/errors/exceptions.dart';
import 'package:gst_expense_scanner/core/services/location_service.dart';
import 'package:gst_expense_scanner/core/theme/glass.dart';
import 'package:gst_expense_scanner/features/auth/presentation/providers/auth_providers.dart';
import 'package:gst_expense_scanner/features/company_config/presentation/company_config_providers.dart';
import 'package:gst_expense_scanner/features/gstin/gstin_lookup.dart';
import 'package:gst_expense_scanner/features/home/presentation/providers/home_providers.dart';
import 'package:gst_expense_scanner/features/review/presentation/providers/review_providers.dart';
import 'package:gst_expense_scanner/features/sync/presentation/sync_providers.dart';
import 'package:gst_expense_scanner/features/uploads/presentation/screens/uploads_screen.dart';
import 'package:gst_expense_scanner/shared/models/company_config.dart';
import 'package:gst_expense_scanner/shared/models/invoice_entity.dart';
import 'package:gst_expense_scanner/shared/widgets/app_scaffold.dart';
import 'package:gst_expense_scanner/shared/widgets/error_view.dart';
import 'package:gst_expense_scanner/shared/widgets/loading_overlay.dart';
import 'package:gst_expense_scanner/shared/widgets/primary_button.dart';

final _amountPattern = RegExp(r'^\d+(\.\d{1,2})?$');
final _gstinPattern = RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');

/// Loads a returned invoice by local id and opens it for editing.
class ResubmitScreen extends ConsumerWidget {
  const ResubmitScreen({super.key, required this.localId});

  final String localId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(uploadDetailProvider(localId));
    return detail.when(
      loading: () => const AppScaffold(
        title: 'Edit & resubmit',
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => AppScaffold(
        title: 'Edit & resubmit',
        body: ErrorView(message: error.toString()),
      ),
      data: (invoice) => invoice == null || !invoice.canResubmit
          ? const AppScaffold(
              title: 'Edit & resubmit',
              body: ErrorView(
                message: 'This invoice can no longer be edited.',
              ),
            )
          : ReviewScreen(resubmit: invoice),
    );
  }
}

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, this.resubmit});

  /// A returned invoice being corrected; null for a fresh scan.
  final InvoiceEntity? resubmit;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _vendorController;
  late final TextEditingController _gstinController;
  late final TextEditingController _invoiceNumberController;
  late final TextEditingController _taxableController;
  late final TextEditingController _cgstController;
  late final TextEditingController _sgstController;
  late final TextEditingController _igstController;
  late final TextEditingController _discountController;
  late final TextEditingController _netController;
  late final TextEditingController _remarksController;
  late final TextEditingController _categoryController;
  final _noteController = TextEditingController();

  DateTime? _invoiceDate;
  String? _dateError;
  String? _gstinWarning;
  bool _submitting = false;
  bool _locating = false;
  LocationCapture? _location;

  bool get _isResubmit => widget.resubmit != null;

  bool get _requiresGps =>
      !_isResubmit &&
      (ref.read(activeCompanyConfigProvider)?.requiresGps ?? false);

  @override
  void initState() {
    super.initState();
    final data =
        widget.resubmit?.editedData ??
        ref.read(reviewDraftProvider)?.editedData ??
        const InvoiceFieldData();
    _vendorController = TextEditingController(text: data.vendorName ?? '');
    _gstinController = TextEditingController(text: data.gstin ?? '');
    _invoiceNumberController = TextEditingController(
      text: data.invoiceNumber ?? '',
    );
    _taxableController = TextEditingController(
      text: _formatNum(data.taxableValue),
    );
    _cgstController = TextEditingController(text: _formatNum(data.cgst));
    _sgstController = TextEditingController(text: _formatNum(data.sgst));
    _igstController = TextEditingController(text: _formatNum(data.igst));
    _discountController = TextEditingController(
      text: _formatNum(data.discount),
    );
    _netController = TextEditingController(text: _formatNum(data.netAmount));
    _remarksController = TextEditingController(text: data.remarks ?? '');
    _categoryController = TextEditingController(
      text: data.expenseCategoryName ?? '',
    );
    _invoiceDate = data.invoiceDate;
    _gstinWarning = _gstinWarningFor(_gstinController.text);

    final draft = ref.read(reviewDraftProvider);
    if (_requiresGps && draft?.latitude == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _captureLocation());
    } else if (draft?.latitude != null) {
      _location = LocationCapture.success(draft!.latitude!, draft.longitude!);
    }
  }

  @override
  void dispose() {
    _vendorController.dispose();
    _gstinController.dispose();
    _invoiceNumberController.dispose();
    _taxableController.dispose();
    _cgstController.dispose();
    _sgstController.dispose();
    _igstController.dispose();
    _discountController.dispose();
    _netController.dispose();
    _remarksController.dispose();
    _categoryController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _formatNum(double? value) =>
      value == null ? '' : value.toStringAsFixed(2);

  double? _parseNum(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned.replaceAll(',', ''));
  }

  String? _validateAmount(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    return _amountPattern.hasMatch(text) ? null : 'Enter an amount like 1250.50';
  }

  String? _gstinWarningFor(String value) {
    final text = value.trim().toUpperCase();
    if (text.isEmpty || _gstinPattern.hasMatch(text)) return null;
    return 'This does not look like a valid GSTIN — please check it';
  }

  String? _dateErrorFor(DateTime? date) {
    if (date == null) return null;
    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
    return date.isAfter(endOfToday)
        ? 'Invoice date cannot be in the future'
        : null;
  }

  InvoiceFieldData _collectEditedData(List<ExpenseCategory> categories) {
    final categoryName = _categoryController.text.trim();
    String? matchedId;
    for (final c in categories) {
      if (c.name.toLowerCase() == categoryName.toLowerCase()) {
        matchedId = c.id;
        break;
      }
    }
    return InvoiceFieldData(
      vendorName: _vendorController.text.trim().isEmpty
          ? null
          : _vendorController.text.trim(),
      gstin: _gstinController.text.trim().isEmpty
          ? null
          : _gstinController.text.trim().toUpperCase(),
      invoiceNumber: _invoiceNumberController.text.trim().isEmpty
          ? null
          : _invoiceNumberController.text.trim(),
      invoiceDate: _invoiceDate,
      taxableValue: _parseNum(_taxableController.text),
      cgst: _parseNum(_cgstController.text),
      sgst: _parseNum(_sgstController.text),
      igst: _parseNum(_igstController.text),
      discount: _parseNum(_discountController.text),
      netAmount: _parseNum(_netController.text),
      expenseCategoryId:
          matchedId ?? widget.resubmit?.editedData.expenseCategoryId,
      expenseCategoryName: categoryName.isEmpty ? null : categoryName,
      remarks: _remarksController.text.trim().isEmpty
          ? null
          : _remarksController.text.trim(),
    );
  }

  Future<void> _captureLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    final result = await ref.read(locationServiceProvider).capture();
    if (!mounted) return;
    if (result.ok) {
      ref
          .read(reviewDraftProvider.notifier)
          .setLocation(latitude: result.latitude, longitude: result.longitude);
    }
    setState(() {
      _locating = false;
      _location = result;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _invoiceDate != null && !_invoiceDate!.isAfter(now)
          ? _invoiceDate!
          : now,
      firstDate: DateTime(2017),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() {
        _invoiceDate = picked;
        _dateError = _dateErrorFor(picked);
      });
    }
  }

  /// Scan files belong to the draft until it is saved; abandoning the
  /// review must not leave them behind.
  void _discardDraftFiles() {
    final draft = ref.read(reviewDraftProvider);
    final localId = draft?.localId;
    if (localId != null) {
      unawaited(ref.read(imageStoreProvider).deleteInvoiceFiles(localId));
    }
    ref.read(reviewDraftProvider.notifier).clear();
  }

  Future<bool> _confirmDiscard() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_isResubmit ? 'Discard changes?' : 'Discard this scan?'),
        content: Text(
          _isResubmit
              ? 'Your edits will not be sent.'
              : 'The scanned invoice has not been saved and will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Brand.danger),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _onBack() async {
    if (_submitting) return;
    final hasDraft = _isResubmit || ref.read(reviewDraftProvider) != null;
    if (hasDraft && !await _confirmDiscard()) return;
    if (!mounted) return;
    if (!_isResubmit) _discardDraftFiles();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  void _retake() {
    _discardDraftFiles();
    context.pushReplacement('/scan-processing');
  }

  bool _validateForm() {
    final dateError = _dateErrorFor(_invoiceDate);
    setState(() => _dateError = dateError);
    final valid = _formKey.currentState!.validate();
    return valid && dateError == null;
  }

  Future<void> _submit() async {
    if (_isResubmit) return _submitResubmission();
    if (!_validateForm()) return;

    final draft = ref.read(reviewDraftProvider);
    if (draft == null || !draft.hasImage) {
      _showSnack('No scan data found. Please scan again.');
      return;
    }

    final auth = ref.read(authStateProvider);
    if (auth is! AuthAuthenticated) {
      context.go('/login');
      return;
    }

    if (_requiresGps && draft.latitude == null) {
      _showSnack('Your company requires location for every bill.');
      unawaited(_captureLocation());
      return;
    }

    final config = ref.read(activeCompanyConfigProvider);
    final categories = config?.categories ?? const [];
    final edited = _collectEditedData(categories);
    ref.read(reviewDraftProvider.notifier).updateEditedData(edited);

    setState(() => _submitting = true);

    try {
      final repo = ref.read(invoiceRepositoryProvider);
      final duplicateEnabled = config?.duplicateCheckEnabled ?? true;
      var duplicateUnchecked = false;

      if (duplicateEnabled && !draft.duplicateOverride) {
        final dup = await repo.checkDuplicate(
          edited,
          excludeLocalId: draft.localId,
        );
        if (!mounted) return;
        duplicateUnchecked = !dup.checked;
        if (dup.isDuplicate) {
          final override = await _showDuplicateDialog(dup.message);
          if (!mounted) return;
          if (!override) {
            setState(() => _submitting = false);
            return;
          }
          ref.read(reviewDraftProvider.notifier).setDuplicateOverride(true);
        }
      }

      final deviceId = await ref
          .read(secureStorageProvider)
          .getOrCreateDeviceId();
      final employee = auth.employee;
      final current = ref.read(reviewDraftProvider) ?? draft;

      final invoice = await repo.createFromScan(
        companyId: employee.companyId,
        employeeId: employee.id,
        branchId: employee.branchId,
        deviceId: deviceId,
        ocrData: draft.ocrData,
        editedData: edited,
        ocrConfidence: draft.ocrConfidence,
        originalImagePath: draft.originalImagePath!,
        compressedImagePath: draft.compressedImagePath!,
        thumbnailPath: draft.thumbnailPath!,
        localId: draft.localId,
        latitude: current.latitude,
        longitude: current.longitude,
        duplicateOverride: current.duplicateOverride,
      );

      await repo.enqueue(invoice.localId);
      ref.read(reviewDraftProvider.notifier).clear();
      ref.read(syncStatusProvider.notifier)
        ..markChanged()
        ..nudge();

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.go('/home');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            duplicateUnchecked
                ? 'Invoice saved. Duplicate check will run when it uploads.'
                : 'Invoice saved and queued for upload',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showSnack('Could not save the invoice: ${_messageFrom(error)}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitResubmission() async {
    final invoice = widget.resubmit!;
    if (!_validateForm()) return;
    final categories =
        ref.read(activeCompanyConfigProvider)?.categories ?? const [];
    final edited = _collectEditedData(categories);
    final note = _noteController.text.trim();

    setState(() => _submitting = true);
    try {
      await ref
          .read(invoiceRepositoryProvider)
          .resubmit(
            invoice: invoice,
            editedData: edited,
            note: note.isEmpty ? null : note,
          );
      final serverId = invoice.serverId;
      if (serverId != null) ref.invalidate(serverInvoiceProvider(serverId));
      ref.read(syncStatusProvider.notifier).markChanged();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Invoice resubmitted for approval')),
      );
    } catch (error) {
      if (!mounted) return;
      _showSnack(
        'Resubmit failed: ${_messageFrom(error)}. '
        'You need a connection to resubmit.',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _messageFrom(Object error) =>
      error is AppException ? error.failure.message : '$error';

  Future<bool> _showDuplicateDialog(String? message) async {
    const title = 'Possible duplicate';
    final detail = message?.trim().replaceAll(RegExp(r'[.!]$'), '');
    final showDetail =
        detail != null &&
        detail.isNotEmpty &&
        detail.toLowerCase() != title.toLowerCase();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(title),
        content: Text(
          showDetail
              ? message!
              : 'An invoice with the same GSTIN, number and date has already '
                    'been submitted. Submit it again only if this is a '
                    'different bill.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit anyway'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(reviewDraftProvider);
    final lowConfidence = !_isResubmit && ref.watch(reviewLowConfidenceProvider);
    final config = ref.watch(activeCompanyConfigProvider);
    final categories = config?.categories ?? const [];
    final title = _isResubmit ? 'Edit & resubmit' : 'Review invoice';

    if (draft == null && !_isResubmit) {
      return AppScaffold(
        title: title,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No invoice to review.'),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Scan invoice',
                expand: false,
                onPressed: () => context.go('/scan-processing'),
              ),
            ],
          ),
        ),
      );
    }

    final imagePath = _isResubmit
        ? null
        : draft!.compressedImagePath ??
              draft.originalImagePath ??
              draft.sourceImagePath;
    final dateLabel = _invoiceDate == null
        ? 'Select date'
        : DateFormat('dd MMM yyyy').format(_invoiceDate!);
    final requiresGps = !_isResubmit && (config?.requiresGps ?? false);
    final ocr = draft?.ocrData ?? const InvoiceFieldData();
    final remarks = widget.resubmit?.adminRemarks;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_onBack());
      },
      child: AppScaffold(
        title: title,
        body: Stack(
          children: [
            Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (remarks != null && remarks.isNotEmpty) ...[
                    GlassCard(
                      tint: Brand.orange,
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.comment_rounded,
                              color: Brand.orange),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('Admin remarks: $remarks'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (lowConfidence)
                    Card(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Theme.of(
                                context,
                              ).colorScheme.onTertiaryContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Low OCR confidence — please verify all fields.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onTertiaryContainer,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (requiresGps) ...[
                    const SizedBox(height: 12),
                    _LocationStatus(
                      locating: _locating,
                      capture: _location,
                      onRetry: _captureLocation,
                      onOpenSettings: (issue) => ref
                          .read(locationServiceProvider)
                          .openSettings(issue),
                    ),
                  ],
                  if (imagePath != null && File(imagePath).existsSync()) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(imagePath),
                        cacheWidth: 1080,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ] else if (_isResubmit) ...[
                    Center(
                      child: InvoiceThumbnail(
                        invoice: widget.resubmit!,
                        size: 160,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _field(
                    _vendorController,
                    'Vendor name',
                    lowConfidence: lowConfidence && ocr.vendorName == null,
                  ),
                  _field(
                    _gstinController,
                    'GSTIN',
                    textCapitalization: TextCapitalization.characters,
                    lowConfidence: lowConfidence && ocr.gstin == null,
                    helperText: _gstinWarning,
                    onChanged: (value) =>
                        setState(() => _gstinWarning = _gstinWarningFor(value)),
                  ),
                  if (_gstinPattern
                      .hasMatch(_gstinController.text.trim().toUpperCase()))
                    GstinVerifyPanel(
                      gstin: _gstinController.text.trim().toUpperCase(),
                      vendorName: _vendorController.text,
                      onUseName: (name) =>
                          setState(() => _vendorController.text = name),
                    ),
                  _field(
                    _invoiceNumberController,
                    'Invoice number',
                    lowConfidence: lowConfidence && ocr.invoiceNumber == null,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Invoice date'),
                    subtitle: Text(
                      _dateError ?? dateLabel,
                      style: _dateError == null
                          ? null
                          : TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: _pickDate,
                  ),
                  _amountField(_taxableController, 'Taxable value'),
                  _amountField(_cgstController, 'CGST'),
                  _amountField(_sgstController, 'SGST'),
                  _amountField(_igstController, 'IGST'),
                  _amountField(_discountController, 'Discount'),
                  _amountField(
                    _netController,
                    'Invoice value',
                    lowConfidence: lowConfidence && ocr.netAmount == null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _categoryController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Category',
                      hintText: 'Type any category name',
                      helperText: categories.isEmpty
                          ? null
                          : 'Suggestions: ${categories.take(5).map((c) => c.name).join(", ")}',
                    ),
                  ),
                  if (categories.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final c in categories.take(8))
                          ActionChip(
                            label: Text(c.name),
                            onPressed: () => setState(
                              () => _categoryController.text = c.name,
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _remarksController,
                    decoration: const InputDecoration(labelText: 'Remarks'),
                    maxLines: 2,
                  ),
                  if (_isResubmit) ...[
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _noteController,
                      maxLength: 500,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Note for your approver (optional)',
                        hintText: 'What did you change?',
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (!_isResubmit) ...[
                    OutlinedButton(
                      onPressed: _submitting ? null : _retake,
                      child: const Text('Retake'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  PrimaryButton(
                    label: _isResubmit ? 'Resubmit' : 'Submit',
                    loading: _submitting,
                    onPressed: _submitting || (requiresGps && _locating)
                        ? null
                        : _submit,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            LoadingOverlay(
              visible: _submitting,
              message: _isResubmit ? 'Sending…' : 'Saving…',
            ),
          ],
        ),
      ),
    );
  }

  Widget _amountField(
    TextEditingController controller,
    String label, {
    bool lowConfidence = false,
  }) {
    return _field(
      controller,
      label,
      keyboard: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      validator: _validateAmount,
      lowConfidence: lowConfidence,
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType keyboard = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool lowConfidence = false,
    String? helperText,
    FormFieldValidator<String>? validator,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        inputFormatters: inputFormatters,
        textCapitalization: textCapitalization,
        validator: validator,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          helperText: helperText,
          helperMaxLines: 2,
          helperStyle: helperText == null
              ? null
              : const TextStyle(color: Brand.warning),
          fillColor: lowConfidence
              ? Theme.of(
                  context,
                ).colorScheme.errorContainer.withValues(alpha: 0.35)
              : null,
        ),
      ),
    );
  }
}

class _LocationStatus extends StatelessWidget {
  const _LocationStatus({
    required this.locating,
    required this.capture,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final bool locating;
  final LocationCapture? capture;
  final VoidCallback onRetry;
  final ValueChanged<LocationIssue> onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final capture = this.capture;
    final ok = capture?.ok ?? false;
    final color = locating
        ? theme.colorScheme.primary
        : ok
        ? Brand.success
        : Brand.danger;
    final issue = capture?.issue;
    final needsSettings =
        issue == LocationIssue.deniedForever ||
        issue == LocationIssue.serviceDisabled;

    return GlassCard(
      tint: color,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (locating)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              else
                Icon(
                  ok ? Icons.location_on_rounded : Icons.location_off_rounded,
                  color: color,
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  locating
                      ? 'Getting your location…'
                      : capture?.message ??
                            'Your company requires location for every bill.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          if (!locating && !ok) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.my_location_rounded, size: 18),
                  label: const Text('Retry'),
                ),
                if (needsSettings)
                  TextButton.icon(
                    onPressed: () => onOpenSettings(issue!),
                    icon: const Icon(Icons.settings_rounded, size: 18),
                    label: const Text('Open settings'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
