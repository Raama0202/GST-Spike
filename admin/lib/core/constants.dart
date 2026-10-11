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
}

abstract final class ApiPaths {
  static const login = '/admin/auth/login';
  static const refresh = '/auth/token/refresh';
  static const logout = '/auth/logout';
  static const dashboard = '/admin/dashboard';
  static const invoices = '/admin/invoices';
  static const employees = '/admin/employees';
  static const categories = '/admin/company/categories';
  static const branches = '/admin/company/branches';
  static const settings = '/admin/company/settings';
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
}
