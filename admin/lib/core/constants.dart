abstract final class AppConstants {
  static const appName = 'GST Expense Admin';
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://gst-expense-scanner.onrender.com/v1',
  );

  /// Demo / Live builds may change the API host without rebuilding.
  static const allowServerOverride = bool.fromEnvironment(
    'ALLOW_SERVER_OVERRIDE',
    defaultValue: false,
  );

  /// Web admin console, where billing and renewals happen.
  static const consoleUrl = String.fromEnvironment(
    'CONSOLE_URL',
    defaultValue: 'https://gst-admin-console.onrender.com',
  );
  static const privacyUrl = String.fromEnvironment(
    'PRIVACY_URL',
    defaultValue: '$consoleUrl/#/privacy',
  );
  static const termsUrl = String.fromEnvironment(
    'TERMS_URL',
    defaultValue: '$consoleUrl/#/terms',
  );

  /// Crash reporting is off unless a DSN is compiled in.
  static const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  static const minPasswordLength = 10;
}

abstract final class ApiPaths {
  static const login = '/admin/auth/login';
  static const registerOptions = '/admin/auth/register/options';
  static const register = '/admin/auth/register';
  static const registerResend = '/admin/auth/register/resend';
  static const registerVerify = '/admin/auth/register/verify';
  static const passwordForgot = '/admin/auth/password/forgot';
  static const passwordReset = '/admin/auth/password/reset';
  static const changePassword = '/admin/auth/password';
  static const refresh = '/auth/token/refresh';
  static const logout = '/auth/logout';
  static const dashboard = '/admin/dashboard';
  static const invoices = '/admin/invoices';
  static const invoicesBulkDecision = '/admin/invoices/bulk-decision';
  static const invoicesExport = '/admin/invoices/export';
  static const employees = '/admin/employees';
  static const categories = '/admin/company/categories';
  static const branches = '/admin/company/branches';
  static const settings = '/admin/company/settings';
  static const companyDelete = '/admin/company/delete';
  static const audit = '/admin/audit';
  static const notifications = '/admin/notifications';
  static const announcements = '/admin/notifications/announcements';
  static const itcStatus = '/admin/itc/status';
  static const itcImport = '/admin/itc/import';
  static const itcImports = '/admin/itc/imports';
  static const itcSummary = '/admin/itc/summary';
  static const itcMatches = '/admin/itc/matches';
  static const itcReconcile = '/admin/itc/reconcile';
  static const itcRemindMissing = '/admin/itc/remind-missing';
  static const itcReminders = '/admin/itc/reminders';
  static const itcExport = '/admin/itc/matches/export';

  /// Unauthenticated endpoints: a 401 here is a real answer, not an expired
  /// access token.
  static const noRefresh = {
    login,
    register,
    registerResend,
    registerVerify,
    passwordForgot,
    passwordReset,
    refresh,
    logout,
  };
}
