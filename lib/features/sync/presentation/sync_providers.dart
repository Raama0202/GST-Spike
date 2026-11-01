import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gst_expense_scanner/core/di/providers.dart';
import 'package:gst_expense_scanner/core/errors/exceptions.dart';

import '../data/sync_engine.dart';

export 'package:gst_expense_scanner/core/di/providers.dart'
    show
        apiClientProvider,
        connectivityProvider,
        imageStoreProvider,
        invoiceLocalDataSourceProvider,
        invoiceRemoteDataSourceProvider,
        invoiceRepositoryProvider,
        localDatabaseProvider,
        secureStorageProvider;

enum SyncStatusView { idle, syncing, error }

class SyncStatusSnapshot {
  const SyncStatusSnapshot({
    required this.state,
    required this.pendingCount,
    this.lastError,
    this.lastSyncedAt,
    this.revision = 0,
  });

  final SyncStatusView state;
  final int pendingCount;
  final String? lastError;
  final DateTime? lastSyncedAt;

  /// Mirrors [SyncEngine.revision]; watch it to reload invoice lists.
  final int revision;

  static const _keep = Object();

  /// Omitting [lastError] keeps the current one; pass `null` to clear it.
  SyncStatusSnapshot copyWith({
    SyncStatusView? state,
    int? pendingCount,
    Object? lastError = _keep,
    DateTime? lastSyncedAt,
    int? revision,
  }) {
    return SyncStatusSnapshot(
      state: state ?? this.state,
      pendingCount: pendingCount ?? this.pendingCount,
      lastError:
          identical(lastError, _keep) ? this.lastError : lastError as String?,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      revision: revision ?? this.revision,
    );
  }
}

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(
    localDataSource: ref.watch(invoiceLocalDataSourceProvider),
    remoteDataSource: ref.watch(invoiceRemoteDataSourceProvider),
    connectivityService: ref.watch(connectivityProvider),
    imageStore: ref.watch(imageStoreProvider),
  );
  ref.onDispose(engine.stop);
  return engine;
});

final pendingUploadCountProvider = FutureProvider<int>((ref) async {
  final local = ref.watch(invoiceLocalDataSourceProvider);
  return local.pendingQueueCount();
});

class SyncStatusNotifier extends StateNotifier<SyncStatusSnapshot> {
  SyncStatusNotifier(this._syncEngine)
      : super(
          const SyncStatusSnapshot(
            state: SyncStatusView.idle,
            pendingCount: 0,
          ),
        );

  final SyncEngine _syncEngine;
  Timer? _pollTimer;

  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(refresh());
    });
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final pending = await _syncEngine.pendingCount();
    if (!mounted) return;
    final error = _syncEngine.lastError;
    if (pending == state.pendingCount &&
        _syncEngine.revision == state.revision &&
        error == state.lastError) {
      return;
    }
    state = state.copyWith(
      pendingCount: pending,
      revision: _syncEngine.revision,
      lastError: error,
    );
  }

  /// [force] retries items still in their backoff window and re-reads the
  /// whole server history (pull-to-refresh, "Sync now").
  Future<void> syncNow({bool force = true}) async {
    state = state.copyWith(state: SyncStatusView.syncing);
    try {
      await _syncEngine.syncNow(force: force);
      final pending = await _syncEngine.pendingCount();
      if (!mounted) return;
      state = state.copyWith(
        state: SyncStatusView.idle,
        pendingCount: pending,
        lastSyncedAt: DateTime.now(),
        revision: _syncEngine.revision,
        lastError: _syncEngine.lastError,
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        state: SyncStatusView.error,
        lastError: error is AppException ? error.failure.message : '$error',
      );
    }
  }

  /// Local edits made outside the engine (delete, retry, resubmit).
  void markChanged() {
    _syncEngine.markChanged();
    unawaited(refresh());
  }

  Future<void> startEngine() async {
    await _syncEngine.start();
    startPolling();
  }

  void nudge() => _syncEngine.nudge();

  void stopEngine() {
    _pollTimer?.cancel();
    _syncEngine.stop();
    state = state.copyWith(state: SyncStatusView.idle);
  }

  /// Stops and lets an in-flight upload finish before data is cleared.
  Future<void> stopEngineAndDrain() async {
    _pollTimer?.cancel();
    await _syncEngine.stopAndDrain();
    if (mounted) state = state.copyWith(state: SyncStatusView.idle);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

final syncStatusProvider =
    StateNotifierProvider<SyncStatusNotifier, SyncStatusSnapshot>((ref) {
  return SyncStatusNotifier(ref.watch(syncEngineProvider));
});
