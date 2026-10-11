import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:gst_expense_scanner/features/auth/presentation/providers/auth_providers.dart';
import 'package:gst_expense_scanner/features/company_config/presentation/company_config_providers.dart';
import 'package:gst_expense_scanner/features/home/presentation/providers/home_providers.dart';
import 'package:gst_expense_scanner/features/review/presentation/providers/review_providers.dart';
import 'package:gst_expense_scanner/features/sync/presentation/sync_providers.dart';
import 'package:gst_expense_scanner/shared/models/company_config.dart';
import 'package:gst_expense_scanner/shared/models/invoice_entity.dart';
import 'package:gst_expense_scanner/shared/widgets/app_scaffold.dart';
import 'package:gst_expense_scanner/shared/widgets/loading_overlay.dart';
import 'package:gst_expense_scanner/shared/widgets/primary_button.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

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

  DateTime? _invoiceDate;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(reviewDraftProvider);
    final data = draft?.editedData ?? const InvoiceFieldData();
    _vendorController = TextEditingController(text: data.vendorName ?? '');
    _gstinController = TextEditingController(text: data.gstin ?? '');
    _invoiceNumberController =
        TextEditingController(text: data.invoiceNumber ?? '');
    _taxableController =
        TextEditingController(text: _formatNum(data.taxableValue));
    _cgstController = TextEditingController(text: _formatNum(data.cgst));
    _sgstController = TextEditingController(text: _formatNum(data.sgst));
    _igstController = TextEditingController(text: _formatNum(data.igst));
    _discountController = TextEditingController(text: _formatNum(data.discount));
    _netController = TextEditingController(text: _formatNum(data.netAmount));
    _remarksController = TextEditingController(text: data.remarks ?? '');
    _categoryController =
        TextEditingController(text: data.expenseCategoryName ?? '');
    _invoiceDate = data.invoiceDate;
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
    super.dispose();
  }

  String _formatNum(double? value) =>
      value == null ? '' : value.toStringAsFixed(2);

  double? _parseNum(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned.replaceAll(',', ''));
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
      expenseCategoryId: matchedId,
      expenseCategoryName: categoryName.isEmpty ? null : categoryName,
      remarks: _remarksController.text.trim().isEmpty
          ? null
          : _remarksController.text.trim(),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _invoiceDate ?? DateTime.now(),
      firstDate: DateTime(2017),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _invoiceDate = picked);
  }

  Future<void> _retake() async {
    ref.read(reviewDraftProvider.notifier).clear();
    context.go('/scan-processing');
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

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

    final config = ref.read(activeCompanyConfigProvider);
    final categories = config?.categories ?? const [];
    final edited = _collectEditedData(categories);
    ref.read(reviewDraftProvider.notifier).updateEditedData(edited);

    setState(() => _submitting = true);

    try {
      final repo = ref.read(invoiceRepositoryProvider);
      final duplicateEnabled = config?.duplicateCheckEnabled ?? true;

      if (duplicateEnabled && !draft.duplicateOverride) {
        final dup = await repo.checkDuplicate(
          edited,
          excludeLocalId: draft.localId,
        );
        if (dup.isDuplicate) {
          if (!mounted) return;
          final override = await _showDuplicateDialog(dup.message);
          if (!override) {
            setState(() => _submitting = false);
            return;
          }
          ref.read(reviewDraftProvider.notifier).setDuplicateOverride(true);
        }
      }

      final deviceId =
          await ref.read(secureStorageProvider).getOrCreateDeviceId();
      final employee = auth.employee;
      final overrideFlag =
          ref.read(reviewDraftProvider)?.duplicateOverride ?? false;

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
        latitude: draft.latitude,
        longitude: draft.longitude,
      );

      if (overrideFlag) {
        await repo.updateEdited(
          localId: invoice.localId,
          editedData: edited,
          duplicateOverride: true,
        );
      }

      await repo.enqueue(invoice.localId);
      ref.read(reviewDraftProvider.notifier).clear();
      ref.invalidate(homeTodayUploadCountProvider);
      await ref.read(syncStatusProvider.notifier).refresh();

      if (!mounted) return;
      context.go('/home');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice saved and queued for upload')),
      );
    } catch (error) {
      if (!mounted) return;
      _showSnack('Submit failed: $error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<bool> _showDuplicateDialog(String? message) async {
    const title = 'Possible duplicate';
    final detail = message?.trim().replaceAll(RegExp(r'[.!]$'), '');
    final showDetail = detail != null &&
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(reviewDraftProvider);
    final lowConfidence = ref.watch(reviewLowConfidenceProvider);
    final config = ref.watch(activeCompanyConfigProvider);
    final categories = config?.categories ?? const [];

    if (draft == null) {
      return AppScaffold(
        title: 'Review invoice',
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

    final imagePath = draft.compressedImagePath ??
        draft.originalImagePath ??
        draft.sourceImagePath;
    final dateLabel = _invoiceDate == null
        ? 'Select date'
        : DateFormat('dd MMM yyyy').format(_invoiceDate!);

    return AppScaffold(
      title: 'Review invoice',
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (lowConfidence)
                  Card(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Theme.of(context)
                                .colorScheme
                                .onTertiaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Low OCR confidence — please verify all fields.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onTertiaryContainer,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (imagePath != null && File(imagePath).existsSync()) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(imagePath),
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _field(
                  _vendorController,
                  'Vendor name',
                  lowConfidence: draft.ocrData.vendorName == null,
                ),
                _field(
                  _gstinController,
                  'GSTIN',
                  textCapitalization: TextCapitalization.characters,
                  lowConfidence: draft.ocrData.gstin == null,
                ),
                _field(
                  _invoiceNumberController,
                  'Invoice number',
                  lowConfidence: draft.ocrData.invoiceNumber == null,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Invoice date'),
                  subtitle: Text(dateLabel),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: _pickDate,
                ),
                _field(
                  _taxableController,
                  'Taxable value',
                  keyboard: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                ),
                _field(
                  _cgstController,
                  'CGST',
                  keyboard: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                ),
                _field(
                  _sgstController,
                  'SGST',
                  keyboard: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                ),
                _field(
                  _igstController,
                  'IGST',
                  keyboard: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                ),
                _field(
                  _discountController,
                  'Discount',
                  keyboard: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                ),
                _field(
                  _netController,
                  'Net amount',
                  keyboard: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                  lowConfidence: draft.ocrData.netAmount == null,
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
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: _submitting ? null : _retake,
                  child: const Text('Retake'),
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  label: 'Submit',
                  loading: _submitting,
                  onPressed: _submitting ? null : _submit,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
          LoadingOverlay(visible: _submitting, message: 'Saving…'),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType keyboard = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool lowConfidence = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        inputFormatters: inputFormatters,
        textCapitalization: textCapitalization,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: lowConfidence
              ? Theme.of(context)
                  .colorScheme
                  .errorContainer
                  .withValues(alpha: 0.35)
              : null,
        ),
      ),
    );
  }
}
