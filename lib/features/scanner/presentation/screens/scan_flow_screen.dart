import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:gst_expense_scanner/core/di/providers.dart';
import 'package:gst_expense_scanner/core/errors/exceptions.dart';
import 'package:gst_expense_scanner/core/errors/failures.dart';
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

      if (!await scanner.validateImagePath(path)) {
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

  Future<void> _processImage(String sourcePath) async {
    final localId = const Uuid().v4();
    ref.read(reviewDraftProvider.notifier).startCapture(sourcePath);

    setState(() => _statusMessage = 'Processing image…');

    try {
      final pipeline = ref.read(imagePipelineProvider);
      final processed = await pipeline.process(
        sourcePath: sourcePath,
        localId: localId,
      );

      ref.read(reviewDraftProvider.notifier).setProcessedImages(
            originalImagePath: processed.originalPath,
            compressedImagePath: processed.compressedPath,
            thumbnailPath: processed.thumbnailPath,
            isBlurry: processed.isBlurry,
            blurVariance: processed.blurVariance,
          );

      if (processed.isBlurry) {
        if (!mounted) return;
        final retake = await _showBlurDialog();
        if (retake) {
          ref.read(reviewDraftProvider.notifier).clear();
          setState(() => _phase = _ScanPhase.choose);
          return;
        }
        setState(() => _blurWarning = true);
      }

      setState(() => _statusMessage = 'Extracting invoice with AI…');

      final ocr = ref.read(ocrServiceProvider);
      OcrRunResult ocrResult;
      try {
        ocrResult = await ocr.runOcr(processed.compressedPath);
      } on AppException catch (e) {
        if (!mounted) return;
        final retake = await _showOcrFailureDialog(_messageFrom(e));
        if (retake) {
          ref.read(reviewDraftProvider.notifier).clear();
          setState(() => _phase = _ScanPhase.choose);
          return;
        }
        rethrow;
      }

      if (!mounted) return;
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

      if (!mounted) return;
      context.go('/review');
    } catch (error) {
      ref.read(reviewDraftProvider.notifier).clear();
      if (!mounted) return;
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
