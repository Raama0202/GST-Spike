import 'package:gst_expense_scanner/core/constants/app_constants.dart';
import 'package:gst_expense_scanner/core/errors/exceptions.dart';
import 'package:gst_expense_scanner/core/errors/failures.dart';
import 'package:gst_expense_scanner/core/network/api_client.dart';
import 'package:gst_expense_scanner/shared/models/notification_entity.dart';

/// Fetches notifications from the backend API.
class NotificationRemoteDataSource {
  NotificationRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  static const pageSize = 50;

  Future<List<AppNotification>> fetchNotifications() async {
    try {
      final response = await _apiClient.get<dynamic>(
        ApiEndpoints.notifications,
        queryParameters: {'pageSize': pageSize},
      );
      final body = response.data;
      final data = body is Map ? body['items'] : body;
      if (data is! List) return const [];

      return data
          .map(
            (item) => AppNotification.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } on AppException {
      rethrow;
    } catch (error) {
      throw AppException(
        ServerFailure('Failed to fetch notifications: $error'),
      );
    }
  }

  Future<void> markRead(List<String> notificationIds) async {
    await _apiClient.post<void>(
      ApiEndpoints.markNotificationRead,
      data: {'ids': notificationIds},
    );
  }
}
