import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/notifications/notification_provider.dart';

/// Stable Firestore document id for an FCM token (`devices/{deviceId}`).
abstract final class FcmDeviceIds {
  static String fromToken(String token) {
    final sanitized = token.replaceAll('/', '_').replaceAll('.', '_');
    if (sanitized.length <= 128) {
      return sanitized;
    }
    return sanitized.substring(sanitized.length - 128);
  }
}

/// FCM token + device registration. Widgets never import `firebase_messaging`.
class FirebaseMessagingDataSource implements NotificationProvider {
  FirebaseMessagingDataSource({
    FirebaseFirestore? firestore,
    FirebaseMessaging? messaging,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseFirestore _firestore;
  final FirebaseMessaging _messaging;

  @override
  Future<Result<void>> requestPermission() async {
    try {
      await _messaging.requestPermission();
      return const Success(null);
    } on Object {
      return const Err(
        PermissionFailure('Notification permission was not granted.'),
      );
    }
  }

  @override
  Future<Result<String?>> getToken() async {
    try {
      return Success(await _messaging.getToken());
    } on Object {
      return const Success(null);
    }
  }

  Stream<String> watchTokenRefresh() => _messaging.onTokenRefresh;

  Stream<Map<String, dynamic>> watchOpenedApp() {
    return FirebaseMessaging.onMessageOpenedApp.map(_payload);
  }

  Stream<Map<String, dynamic>> watchForegroundMessage() {
    return FirebaseMessaging.onMessage.map(_payload);
  }

  Future<Map<String, dynamic>?> initialMessage() async {
    final message = await _messaging.getInitialMessage();
    return message == null ? null : _payload(message);
  }

  Map<String, dynamic> _payload(RemoteMessage message) {
    return Map<String, dynamic>.from(message.data);
  }

  /// Writes `users/{uid}/devices/{deviceId}` and the legacy `fcmTokens` path.
  Future<void> registerDevice({
    required String uid,
    required String token,
  }) async {
    final deviceId = FcmDeviceIds.fromToken(token);
    final payload = <String, dynamic>{
      'token': token,
      'platform': defaultTargetPlatform.name,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final batch = _firestore.batch();
    batch.set(_firestore.doc(FirestorePaths.device(uid, deviceId)), payload);
    batch.set(_firestore.doc(FirestorePaths.fcmToken(uid, deviceId)), payload);
    await batch.commit();
  }

  Future<void> unregisterDevice({
    required String uid,
    required String token,
  }) async {
    final deviceId = FcmDeviceIds.fromToken(token);
    final batch = _firestore.batch();
    batch.delete(_firestore.doc(FirestorePaths.device(uid, deviceId)));
    batch.delete(_firestore.doc(FirestorePaths.fcmToken(uid, deviceId)));
    await batch.commit();
  }

  @override
  Stream<AppNotification> watchForeground() {
    return watchForegroundMessage().map((data) {
      return AppNotification(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: (data['title'] as String?) ?? '',
        body: (data['body'] as String?) ?? '',
        createdAt: DateTime.now(),
        route: data['route'] as String?,
      );
    });
  }
}
