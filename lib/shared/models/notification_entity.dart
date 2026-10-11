import 'package:equatable/equatable.dart';

import 'invoice_entity.dart';

class AppNotification extends Equatable {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
    this.invoiceLocalId,
    this.invoiceServerId,
  });

  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;
  final String? invoiceLocalId;
  final String? invoiceServerId;

  AppNotification copyWith({bool? read}) => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    createdAt: createdAt,
    read: read ?? this.read,
    invoiceLocalId: invoiceLocalId,
    invoiceServerId: invoiceServerId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'title': title,
    'body': body,
    'createdAt': createdAt.toIso8601String(),
    'read': read,
    'invoiceLocalId': invoiceLocalId,
    'invoiceServerId': invoiceServerId,
  };

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      type: NotificationType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => NotificationType.companyAnnouncement,
      ),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      read: json['read'] as bool? ?? false,
      invoiceLocalId: json['invoiceLocalId'] as String?,
      invoiceServerId: json['invoiceServerId'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, read, type];
}

class UploadQueueItem extends Equatable {
  const UploadQueueItem({
    required this.localInvoiceId,
    required this.enqueuedAt,
    required this.attempts,
    this.nextAttemptAt,
    this.lastError,
    this.uploadSessionId,
  });

  final String localInvoiceId;
  final DateTime enqueuedAt;
  final int attempts;
  final DateTime? nextAttemptAt;
  final String? lastError;
  final String? uploadSessionId;

  UploadQueueItem copyWith({
    int? attempts,
    DateTime? nextAttemptAt,
    String? lastError,
    String? uploadSessionId,
  }) {
    return UploadQueueItem(
      localInvoiceId: localInvoiceId,
      enqueuedAt: enqueuedAt,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastError: lastError ?? this.lastError,
      uploadSessionId: uploadSessionId ?? this.uploadSessionId,
    );
  }

  Map<String, dynamic> toJson() => {
    'localInvoiceId': localInvoiceId,
    'enqueuedAt': enqueuedAt.toIso8601String(),
    'attempts': attempts,
    'nextAttemptAt': nextAttemptAt?.toIso8601String(),
    'lastError': lastError,
    'uploadSessionId': uploadSessionId,
  };

  factory UploadQueueItem.fromJson(Map<String, dynamic> json) {
    return UploadQueueItem(
      localInvoiceId: json['localInvoiceId'] as String,
      enqueuedAt: DateTime.parse(json['enqueuedAt'] as String),
      attempts: json['attempts'] as int? ?? 0,
      nextAttemptAt: json['nextAttemptAt'] != null
          ? DateTime.tryParse(json['nextAttemptAt'] as String)
          : null,
      lastError: json['lastError'] as String?,
      uploadSessionId: json['uploadSessionId'] as String?,
    );
  }

  @override
  List<Object?> get props => [localInvoiceId, attempts];
}
