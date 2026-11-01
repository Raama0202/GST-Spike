import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:gst_expense_scanner/core/di/providers.dart';
import 'package:gst_expense_scanner/core/errors/exceptions.dart';
import 'package:gst_expense_scanner/core/errors/failures.dart';
import 'package:gst_expense_scanner/core/storage/local_database.dart';
import 'package:gst_expense_scanner/features/company_config/presentation/company_config_providers.dart';
import 'package:gst_expense_scanner/features/ocr/data/ocr_service.dart';
import 'package:gst_expense_scanner/features/review/presentation/providers/review_providers.dart';
import 'package:gst_expense_scanner/shared/widgets/loading_overlay.dart';
import 'package:gst_expense_scanner/shared/widgets/primary_button.dart';

enum _ScanPhase { choose, processing, error }

class ScanFlowScreen extends ConsumerStatefulWidget {
  const ScanFlowScreen({super.key});

  @override
  ConsumerState<ScanFlowScreen> createState() => _ScanFlowScreenState();
}

class _ScanFlowScreenState extends ConsumerState<ScanFlowScreen> {
  _ScanPhase _phase = _ScanPhase.choose;
  String? _errorMessage;
  String? _statusMessage;
  bool _blurWarning = false;
  String? _localId;
  late final InvoiceImageStore _imageStore;

  @override
  void initState() {
    super.initState();
    _imageStore = ref.read(imageStoreProvider);
  }

  @override
  void dispose() {
    final localId = _localId;
    if (localId != null) unawaited(_imageStore.deleteInvoiceFiles(localId));
    super.dispose();
  }

  Future<void> _capture({required bool fromGallery}) async {
    setState(() {
      _phase = _ScanPhase.processing;
      _errorMessage = null;
      _statusMessage = fromGallery ? 'Opening gallery…' : 'Opening scanner…';
      _blurWarning = false;
    });

    try {
      final scanner = ref.read(documentScannerProvider);
      final path = fromGallery
          ? await scanner.pickFromGallery()
          : await scanner.scanDocument();

      if (!mounted) return;
      if (path == null) {
        setState(() => _phase = _ScanPhase.choose);
        return;
      }

      final valid = await scanner.validateImagePath(path);
      if (!mounted) return;
      if (!valid) {
        setState(() {
          _phase = _ScanPhase.error;
          _errorMessage = 'Selected image is not available. Please try again.';
        });
        return;
      }

      await _processImage(path);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _ScanPhase.error;
        _errorMessage = _messageFrom(error);
      });
    }
  }

  /// Drops the draft and the image files written for it, so abandoned scans
  /// do not pile up in app storage.
  void _discard(String? localId) {
    if (localId == null) return;
    if (_localId == localId) _localId = null;
    unawaited(_imageStore.deleteInvoiceFiles(localId));
  }

  Future<void> _processImage(String sourcePath) async {
    final localId = const Uuid().v4();
    _localId = localId;
    ref.read(reviewDraftProvider.notifier).startCapture(sourcePath);

    setState(() => _statusMessage = 'Processing image…');

    try {
      final pipeline = ref.read(imagePipelineProvider);
      final processed = await pipeline.process(
        sourcePath: sourcePath,
        localId: localId,
      );
      if (!mounted) {
        _discard(localId);
        return;
      }

      ref.read(reviewDraftProvider.notifier).setProcessedImages(
            originalImagePath: processed.originalPath,
            compressedImagePath: processed.compressedPath,
            thumbnailPath: processed.thumbnailPath,
            isBlurry: processed.isBlurry,
            blurVariance: processed.blurVariance,
          );

      if (processed.isBlurry) {
        final retake = await _showBlurDialog();
        if (!mounted) {
        _discard(localId);
        return;
      }
        if (retake) {
          ref.read(reviewDraftProvider.notifier).clear();
          _discard(localId);
          setState(() => _phase = _ScanPhase.choose);
          return;
        }
        setState(() => _blurWarning = true);
      }

      setState(() => _statusMessage = 'Extracting invoice with AI…');

      final ocr = ref.read(ocrServiceProvider);
      OcrRunResult ocrResult;
      try {
        // The full-quality image: the upload rendition can drop to JPEG
        // quality 40 to fit 1 MB, which blurs handwriting.
        ocrResult = await ocr.runOcr(
          processed.originalPath,
          identity: ref.read(activeCompanyConfigProvider)?.identity,
        );
      } on AppException catch (e) {
        if (!mounted) {
        _discard(localId);
        return;
      }
        final retake = await _showOcrFailureDialog(_messageFrom(e));
        if (!mounted) {
        _discard(localId);
        return;
      }
        if (retake) {
          ref.read(reviewDraftProvider.notifier).clear();
          _discard(localId);
          setState(() => _phase = _ScanPhase.choose);
          return;
        }
        rethrow;
      }

      if (!mounted) {
        _discard(localId);
        return;
      }
      setState(() {
        _statusMessage = ocrResult.source == OcrExtractionSource.ai
            ? 'AI extraction complete'
            : 'On-device OCR complete';
      });

      ref.read(reviewDraftProvider.notifier)
        ..setLocalId(localId)
        ..setOcrResult(
          ocrData: ocrResult.data,
          editedData: ocrResult.data,
          ocrConfidence: ocrResult.confidence,
          rawOcrText: ocrResult.rawText,
        );

      // The review screen owns the files from here on.
      _localId = null;
      context.pushReplacement('/review');
    } catch (error) {
      _discard(localId);
      if (!mounted) return;
      ref.read(reviewDraftProvider.notifier).clear();
      setState(() {
        _phase = _ScanPhase.error;
        _errorMessage = _messageFrom(error);
      });
    }
  }

  Future<bool> _showBlurDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Image may be blurry'),
        content: const Text(
          'The captured image appears out of focus. Retake for better extraction accuracy?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continue anyway'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Retake'),
          ),
        ],
      ),
    );
    return result ?? true;
  }

  Future<bool> _showOcrFailureDialog(String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Extraction failed'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Retake'),
          ),
        ],
      ),
    );
    return result ?? true;
  }

  String _messageFrom(Object error) {
    if (error is AppException) {
      return error.failure.message;
    }
    if (error is AppFailure) return error.message;
    return error.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = ref.watch(reviewDraftProvider);
    final previewPath = draft?.thumbnailPath ??
        draft?.compressedImagePath ??
        draft?.sourceImagePath;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan invoice'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            ref.read(reviewDraftProvider.notifier).clear();
            _discard(_localId);
            context.go('/home');
          },
        ),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_blurWarning)
                  Card(
                    color: theme.colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Proceeding with a blurry image — verify fields carefully.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                if (previewPath != null && File(previewPath).existsSync()) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(previewPath),
                      cacheWidth: 1080,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
                const Spacer(),
                if (_phase == _ScanPhase.choose || _phase == _ScanPhase.error) ...[
                  if (_phase == _ScanPhase.error && _errorMessage != null) ...[
                    Text(
                      _errorMessage!,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  PrimaryButton(
                    label: 'Scan with camera',
                    icon: Icons.document_scanner_outlined,
                    onPressed: () => _capture(fromGallery: false),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => _capture(fromGallery: true),
                    child: const Text('Choose from gallery'),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
          LoadingOverlay(
            visible: _phase == _ScanPhase.processing,
            message: _statusMessage,
          ),
        ],
      ),
    );
  }
}
