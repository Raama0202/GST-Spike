import 'package:gst_expense_scanner/core/errors/exceptions.dart';
import 'package:gst_expense_scanner/core/utils/result.dart';
import 'package:gst_expense_scanner/features/company_config/data/company_config_local_datasource.dart';
import 'package:gst_expense_scanner/features/company_config/data/company_config_remote_datasource.dart';
import 'package:gst_expense_scanner/features/company_config/domain/company_config_repository.dart';
import 'package:gst_expense_scanner/shared/models/company_config.dart';

class CompanyConfigRepositoryImpl implements CompanyConfigRepository {
  CompanyConfigRepositoryImpl({
    required CompanyConfigRemoteDataSource remote,
    required CompanyConfigLocalDataSource local,
  })  : _remote = remote,
        _local = local;

  final CompanyConfigRemoteDataSource _remote;
  final CompanyConfigLocalDataSource _local;

  @override
  Future<Result<CompanyConfig>> fetchAndCache() async {
    try {
      final config = await _remote.fetchConfig();
      await _local.saveConfig(config);
      return Success(config);
    } catch (e) {
      return FailureResult(ExceptionMapper.fromObject(e));
    }
  }

  @override
  CompanyConfig? readCached() => _local.readConfig();

  @override
  Future<Result<CompanyConfig>> refresh() => fetchAndCache();
}
