import 'package:gst_expense_scanner/core/constants/app_constants.dart';
import 'package:gst_expense_scanner/core/errors/exceptions.dart';
import 'package:gst_expense_scanner/core/errors/failures.dart';
import 'package:gst_expense_scanner/core/network/api_client.dart';
import 'package:gst_expense_scanner/shared/models/company_config.dart';

class CompanyConfigRemoteDataSource {
  CompanyConfigRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<CompanyConfig> fetchConfig() async {
    final response = await _apiClient.get<dynamic>(ApiEndpoints.companyConfig);
    return CompanyConfig.fromJson(_asMap(response.data));
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw AppException(
      const UnexpectedFailure('Unexpected company configuration response.'),
    );
  }
}
