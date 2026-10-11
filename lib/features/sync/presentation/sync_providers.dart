import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gst_expense_scanner/core/di/providers.dart';

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

  SyncStatusSnapshot copyWith({
    SyncStatusView? state,
    int? pendingCount,
    String? lastError,
    DateTime? lastSyncedAt,
    int? revision,
  }) {
    return SyncStatusSnapshot(
      state: state ?? this.state,
      pendingCount: pendingCount ?? this.pendingCount,
      lastError: lastError,
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
    if (pending == state.pendingCount &&
        _syncEngine.revision == state.revision) {
      return;
    }
    state = state.copyWith(
      pendingCount: pending,
      revision: _syncEngine.revision,
      lastError: state.lastError,
    );
  }

  Future<void> syncNow() async {
    state = state.copyWith(state: SyncStatusView.syncing, lastError: null);
    try {
      await _syncEngine.syncNow();
      final pending = await _syncEngine.pendingCount();
      state = state.copyWith(
        state: SyncStatusView.idle,
        pendingCount: pending,
        lastSyncedAt: DateTime.now(),
        revision: _syncEngine.revision,
      );
    } catch (error) {
      state = state.copyWith(
        state: SyncStatusView.error,
        lastError: error.toString(),
      );
    }
  }

  Future<void> startEngine() async {
    await _syncEngine.start();
    startPolling();
  }

  void stopEngine() {
    _pollTimer?.cancel();
    _syncEngine.stop();
    state = state.copyWith(state: SyncStatusView.idle);
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
