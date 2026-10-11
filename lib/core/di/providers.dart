import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gst_expense_scanner/core/network/api_client.dart';
import 'package:gst_expense_scanner/core/security/secure_storage_service.dart';
import 'package:gst_expense_scanner/core/storage/local_database.dart';
import 'package:gst_expense_scanner/features/auth/data/datasources/auth_local_datasource.dart';
import 'package:gst_expense_scanner/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:gst_expense_scanner/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:gst_expense_scanner/features/auth/domain/repositories/auth_repository.dart';
import 'package:gst_expense_scanner/features/auth/presentation/providers/auth_providers.dart'
    as auth;
import 'package:gst_expense_scanner/features/company_config/data/company_config_local_datasource.dart';
import 'package:gst_expense_scanner/features/company_config/data/company_config_remote_datasource.dart';
import 'package:gst_expense_scanner/features/company_config/data/company_config_repository_impl.dart';
import 'package:gst_expense_scanner/features/company_config/domain/company_config_repository.dart';
import 'package:gst_expense_scanner/features/company_config/presentation/company_config_providers.dart'
    as company;
import 'package:gst_expense_scanner/features/ocr/data/ai_invoice_extract_remote_datasource.dart';
import 'package:gst_expense_scanner/features/ocr/data/ocr_service.dart';
import 'package:gst_expense_scanner/features/scanner/data/document_scanner_service.dart';
import 'package:gst_expense_scanner/features/scanner/data/image_pipeline_service.dart';
import 'package:gst_expense_scanner/features/uploads/data/datasources/invoice_local_datasource.dart';
import 'package:gst_expense_scanner/features/uploads/data/datasources/invoice_remote_datasource.dart';
import 'package:gst_expense_scanner/features/uploads/data/repositories/invoice_repository_impl.dart';
import 'package:gst_expense_scanner/features/uploads/domain/repositories/invoice_repository.dart';

// ── Core storage ─────────────────────────────────────────────────────────────

final secureStorageProvider = Provider<SecureStorageService>(
  (ref) => SecureStorageService(),
);

final localDatabaseProvider = Provider<LocalDatabase>((ref) {
  return LocalDatabase(ref.watch(secureStorageProvider));
});

final imageStoreProvider = Provider<InvoiceImageStore>(
  (ref) => InvoiceImageStore(),
);

final connectivityProvider = Provider<ConnectivityService>(
  (ref) => ConnectivityService(),
);

// ── API client (token refresh uses auth repo lazily to avoid circular deps) ─

/// Auth-only client without refresh interceptor — breaks the provider cycle.
final authApiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    secureStorage: ref.watch(secureStorageProvider),
    onRefreshToken: () async => false,
  );
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    secureStorage: ref.watch(secureStorageProvider),
    onRefreshToken: () async {
      final result =
          await ref.read(authRepositoryImplProvider).refreshSession();
      return result.fold(
        onSuccess: (refreshed) => refreshed,
        onFailure: (_) => false,
      );
    },
  );
});

// ── Auth ─────────────────────────────────────────────────────────────────────

final authLocalDataSourceProvider = Provider<AuthLocalDataSource>((ref) {
  return AuthLocalDataSource(
    database: ref.watch(localDatabaseProvider),
    secureStorage: ref.watch(secureStorageProvider),
  );
});

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  return AuthRemoteDataSource(ref.watch(authApiClientProvider));
});

final authRepositoryImplProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(
    remote: ref.watch(authRemoteDataSourceProvider),
    local: ref.watch(authLocalDataSourceProvider),
    database: ref.watch(localDatabaseProvider),
  );
});

// ── Company config ───────────────────────────────────────────────────────────

final companyConfigLocalDataSourceProvider =
    Provider<CompanyConfigLocalDataSource>((ref) {
  return CompanyConfigLocalDataSource(
    database: ref.watch(localDatabaseProvider),
    secureStorage: ref.watch(secureStorageProvider),
  );
});

final companyConfigRemoteDataSourceProvider =
    Provider<CompanyConfigRemoteDataSource>((ref) {
  return CompanyConfigRemoteDataSource(ref.watch(apiClientProvider));
});

final companyConfigRepositoryImplProvider =
    Provider<CompanyConfigRepository>((ref) {
  return CompanyConfigRepositoryImpl(
    remote: ref.watch(companyConfigRemoteDataSourceProvider),
    local: ref.watch(companyConfigLocalDataSourceProvider),
  );
});

// ── Invoices ─────────────────────────────────────────────────────────────────

final invoiceLocalDataSourceProvider = Provider<InvoiceLocalDataSource>((ref) {
  return InvoiceLocalDataSource(ref.watch(localDatabaseProvider));
});

final invoiceRemoteDataSourceProvider = Provider<InvoiceRemoteDataSource>((ref) {
  return InvoiceRemoteDataSource(ref.watch(apiClientProvider));
});

final invoiceRepositoryProvider = Provider<InvoiceRepository>((ref) {
  return InvoiceRepositoryImpl(
    localDataSource: ref.watch(invoiceLocalDataSourceProvider),
    remoteDataSource: ref.watch(invoiceRemoteDataSourceProvider),
  );
});

// ── Scanner / OCR ────────────────────────────────────────────────────────────

final documentScannerProvider = Provider<DocumentScannerService>((ref) {
  final service = DocumentScannerService();
  ref.onDispose(service.dispose);
  return service;
});

final imagePipelineProvider = Provider<ImagePipelineService>((ref) {
  return ImagePipelineService(imageStore: ref.watch(imageStoreProvider));
});

final ocrServiceProvider = Provider<OcrService>((ref) {
  final service = OcrService(
    aiExtractor: AiInvoiceExtractRemoteDataSource(ref.watch(apiClientProvider)),
    connectivity: ref.watch(connectivityProvider),
  );
  ref.onDispose(service.close);
  return service;
});

// ── Bootstrap overrides for feature-level provider stubs ─────────────────────

List<Override> get appProviderOverrides => [
      auth.authRepositoryProvider.overrideWith(
        (ref) => ref.watch(authRepositoryImplProvider),
      ),
      company.companyConfigRepositoryProvider.overrideWith(
        (ref) => ref.watch(companyConfigRepositoryImplProvider),
      ),
    ];
