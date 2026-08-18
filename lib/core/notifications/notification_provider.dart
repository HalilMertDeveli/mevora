import 'package:mevora/core/errors/result.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.route,
    this.isRead = false,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final String? route;
  final bool isRead;

  AppNotification copyWith({
    String? id,
    String? title,
    String? body,
    DateTime? createdAt,
    String? route,
    bool? isRead,
  }) {
    return AppNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      route: route ?? this.route,
      isRead: isRead ?? this.isRead,
    );
  }
}

/// Push / FCM port. UI never imports firebase_messaging.
abstract class NotificationProvider {
  Future<Result<void>> requestPermission();

  Future<Result<String?>> getToken();

  Stream<AppNotification> watchForeground();
}
