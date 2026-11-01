import 'dart:io';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../constants/app_constants.dart';
import '../security/secure_storage_service.dart';

/// Opens encrypted Hive boxes. Invoice/queue boxes are tenant-scoped.
class LocalDatabase {
  LocalDatabase(this._secureStorage);

  final SecureStorageService _secureStorage;

  Box<dynamic>? _session;
  Box<dynamic>? _companyConfig;
  Box<dynamic>? _invoices;
  Box<dynamic>? _uploadQueue;
  Box<dynamic>? _notifications;
  Box<dynamic>? _meta;

  bool _initialized = false;
  String? _tenantSuffix;

  bool get isInitialized => _initialized;

  /// Company id of the open invoice/queue boxes (`global` before sign-in).
  String get tenantSuffix => _tenantSuffix ?? 'global';

  Box<dynamic> get session => _require(_session, HiveBoxes.session);
  Box<dynamic> get companyConfig =>
      _require(_companyConfig, HiveBoxes.companyConfig);
  Box<dynamic> get invoices => _require(_invoices, HiveBoxes.invoices);
  Box<dynamic> get uploadQueue =>
      _require(_uploadQueue, HiveBoxes.uploadQueue);
  Box<dynamic> get notifications =>
      _require(_notifications, HiveBoxes.notifications);
  Box<dynamic> get meta => _require(_meta, HiveBoxes.meta);

  Future<void> initialize() async {
    if (_initialized) return;
    await Hive.initFlutter();
    final key = await _secureStorage.getOrCreateHiveKey();
    final cipher = HiveAesCipher(key);

    _meta = await Hive.openBox<dynamic>(
      HiveBoxes.meta,
      encryptionCipher: cipher,
    );
    _session = await Hive.openBox<dynamic>(
      HiveBoxes.session,
      encryptionCipher: cipher,
    );
    _companyConfig = await Hive.openBox<dynamic>(
      HiveBoxes.companyConfig,
      encryptionCipher: cipher,
    );
    _notifications = await Hive.openBox<dynamic>(
      HiveBoxes.notifications,
      encryptionCipher: cipher,
    );

    await openTenantBoxes(null, cipher: cipher);
    _initialized = true;
  }

  Future<void> openTenantBoxes(
    String? companyId, {
    HiveAesCipher? cipher,
  }) async {
    final suffix =
        (companyId == null || companyId.isEmpty) ? 'global' : companyId;
    if (_tenantSuffix == suffix &&
        _invoices != null &&
        _uploadQueue != null) {
      return;
    }

    final key =
        cipher ?? HiveAesCipher(await _secureStorage.getOrCreateHiveKey());
    final invoiceName = '${HiveBoxes.invoices}_$suffix';
    final queueName = '${HiveBoxes.uploadQueue}_$suffix';

    if (_invoices != null && _invoices!.isOpen) await _invoices!.close();
    if (_uploadQueue != null && _uploadQueue!.isOpen) {
      await _uploadQueue!.close();
    }

    _invoices = await Hive.openBox<dynamic>(invoiceName, encryptionCipher: key);
    _uploadQueue =
        await Hive.openBox<dynamic>(queueName, encryptionCipher: key);
    _tenantSuffix = suffix;
  }

  /// Re-reads the tenant boxes from disk after the background worker (another
  /// isolate with its own in-memory copy) has written to them.
  Future<void> reloadTenantBoxes() async {
    final suffix = _tenantSuffix;
    if (suffix == null) return;
    _tenantSuffix = null;
    await openTenantBoxes(suffix == 'global' ? null : suffix);
  }

  /// Meta key for the incremental `/invoices/mine` cursor of this tenant.
  String get statusPullKey => 'statusPull_$tenantSuffix';

  Future<void> clearTenantData() async {
    await invoices.clear();
    await uploadQueue.clear();
    // Forces a full history import on the next sign-in.
    await meta.delete(statusPullKey);
  }

  Future<void> clearAllUserData() async {
    await session.clear();
    await companyConfig.clear();
    await notifications.clear();
    await clearTenantData();
  }

  Box<dynamic> _require(Box<dynamic>? box, String name) {
    if (box == null || !box.isOpen) {
      throw StateError('Hive box "$name" is not open.');
    }
    return box;
  }

  Future<void> dispose() async {
    await Hive.close();
    _initialized = false;
  }
}

/// File paths for original / compressed / thumbnail invoice images.
class InvoiceImageStore {
  Future<Directory> _root() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/invoices');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> originalFile(String localId) async {
    final root = await _root();
    return File('${root.path}/$localId/original.jpg');
  }

  Future<File> compressedFile(String localId) async {
    final root = await _root();
    return File('${root.path}/$localId/compressed.jpg');
  }

  Future<File> thumbnailFile(String localId) async {
    final root = await _root();
    return File('${root.path}/$localId/thumb.jpg');
  }

  Future<Directory> ensureInvoiceDir(String localId) async {
    final root = await _root();
    final dir = Directory('${root.path}/$localId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> deleteInvoiceFiles(String localId) async {
    final root = await _root();
    final dir = Directory('${root.path}/$localId');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Deletes the per-invoice folders holding [paths]. Anything outside the
  /// image store (e.g. a gallery photo) is left alone. Never throws.
  Future<void> deleteForPaths(Iterable<String?> paths) async {
    try {
      final root = (await _root()).absolute.path;
      final dirs = <String>{
        for (final path in paths)
          if (path != null && path.isNotEmpty) File(path).absolute.parent.path,
      };
      for (final dir in dirs) {
        if (dir == root || !dir.startsWith(root)) continue;
        final directory = Directory(dir);
        if (await directory.exists()) await directory.delete(recursive: true);
      }
    } catch (_) {}
  }

  /// Removes a single file, ignoring errors.
  Future<void> deleteFile(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
