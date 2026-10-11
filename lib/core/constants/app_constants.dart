class ApiEndpoints {
  ApiEndpoints._();

  static const String requestOtp = '/auth/otp/request';
  static const String verifyOtp = '/auth/otp/verify';
  static const String refreshToken = '/auth/token/refresh';
  static const String logout = '/auth/logout';
  static const String me = '/employees/me';
  static const String companyConfig = '/company/config';
  static const String invoices = '/invoices';
  static const String invoiceDuplicateCheck = '/invoices/duplicate-check';
  static const String invoiceUpload = '/invoices/upload';
  static const String invoiceExtract = '/invoices/extract';
  static const String invoiceExtractStatus = '/invoices/extract/status';
  static const String myInvoices = '/invoices/mine';
  static const String notifications = '/notifications';
  static const String markNotificationRead = '/notifications/read';
  static const String deviceRegister = '/devices/register';
}

class StorageKeys {
  StorageKeys._();

  static const String accessToken = 'access_token';
  static const String refreshToken = 'refresh_token';
  static const String hiveEncryptionKey = 'hive_encryption_key';
  static const String companyId = 'company_id';
  static const String employeeId = 'employee_id';
  static const String rememberLogin = 'remember_login';
  static const String deviceId = 'device_id';
  static const String lastConfigSyncAt = 'last_config_sync_at';
  static const String apiBaseUrlOverride = 'api_base_url_override';
}

class HiveBoxes {
  HiveBoxes._();

  static const String session = 'session';
  static const String companyConfig = 'company_config';
  static const String invoices = 'invoices';
  static const String uploadQueue = 'upload_queue';
  static const String notifications = 'notifications';
  static const String meta = 'meta';
}

class AppConstants {
  AppConstants._();

  static const int otpLength = 6;
  static const int otpResendSeconds = 30;
  static const int maxUploadImageBytes = 1024 * 1024;
  static const int thumbnailMaxEdge = 320;
  static const double blurVarianceThreshold = 80;
  static const double lowOcrConfidenceThreshold = 0.55;
  static const int syncMaxAttempts = 8;
  static const Duration syncBaseBackoff = Duration(seconds: 2);
  static const Duration tokenRefreshSkew = Duration(minutes: 2);
  static const String appName = 'GST Expense Scanner';
}
