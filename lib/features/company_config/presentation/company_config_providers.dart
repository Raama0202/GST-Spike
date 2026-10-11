import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gst_expense_scanner/features/company_config/domain/company_config_repository.dart';
import 'package:gst_expense_scanner/shared/models/company_config.dart';

/// Overridden during app bootstrap with a concrete [CompanyConfigRepository].
final companyConfigRepositoryProvider = Provider<CompanyConfigRepository>((ref) {
  throw UnimplementedError(
    'companyConfigRepositoryProvider must be overridden in DI.',
  );
});

final companyConfigStateProvider =
    StateNotifierProvider<CompanyConfigNotifier, CompanyConfig?>(
  CompanyConfigNotifier.new,
);

class CompanyConfigNotifier extends StateNotifier<CompanyConfig?> {
  CompanyConfigNotifier(this._ref) : super(null);

  final Ref _ref;

  CompanyConfigRepository get _repository =>
      _ref.read(companyConfigRepositoryProvider);

  Future<void> loadCached() async {
    state = _repository.readCached();
  }

  Future<bool> refresh() async {
    final result = await _repository.refresh();
    return result.fold(
      onSuccess: (config) {
        state = config;
        return true;
      },
      onFailure: (_) => false,
    );
  }

  void setConfig(CompanyConfig config) {
    state = config;
  }

  void clear() {
    state = null;
  }
}

/// Convenience read-only provider for widgets.
final activeCompanyConfigProvider = Provider<CompanyConfig?>((ref) {
  return ref.watch(companyConfigStateProvider);
});

final companyBrandColorProvider = Provider((ref) {
  return ref.watch(activeCompanyConfigProvider)?.brandColor;
});
