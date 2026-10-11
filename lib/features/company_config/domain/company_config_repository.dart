import 'package:gst_expense_scanner/core/utils/result.dart';
import 'package:gst_expense_scanner/shared/models/company_config.dart';

abstract class CompanyConfigRepository {
  Future<Result<CompanyConfig>> fetchAndCache();

  CompanyConfig? readCached();

  Future<Result<CompanyConfig>> refresh();
}
