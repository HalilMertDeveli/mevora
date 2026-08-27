import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/notifications/notification_provider.dart';
import 'package:mevora/features/notifications/data/datasources/firebase_messaging_data_source.dart';
import 'package:mevora/features/notifications/domain/models/notification_prefs.dart';

class FirebaseNotificationDataSource
    implements NotificationRepository, NotificationProvider {
  FirebaseNotificationDataSource({
    FirebaseFirestore? firestore,
    FirebaseMessaging? messaging,
    FirebaseMessagingDataSource? messagingDataSource,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _messaging = messagingDataSource ??
           FirebaseMessagingDataSource(firestore: firestore, messaging: messaging);

  final FirebaseFirestore _firestore;
  final FirebaseMessagingDataSource _messaging;

  CollectionReference<Map<String, dynamic>> get _notifications =>
      _firestore.collection(FirestorePaths.notifications);

  CollectionReference<Map<String, dynamic>> get _settings =>
      _firestore.collection(FirestorePaths.userSettings);

  @override
  Stream<NotificationPrefs> watchPrefs(String uid) {
    return _settings.doc(uid).snapshots().map((snap) {
      return _prefsFrom(snap.data() ?? const {});
    });
  }

  @override
  Future<NotificationPrefs> loadPrefs(String uid) async {
    final snap = await _settings.doc(uid).get();
    return _prefsFrom(snap.data() ?? const {});
  }

  @override
  Future<void> savePrefs(String uid, NotificationPrefs prefs) {
    return _settings.doc(uid).set({
      'messageNotifications': prefs.messageNotifications,
      'matchNotifications': prefs.matchNotifications,
      'mevoraHourReminders': prefs.mevoraHourReminders,
      'showOnlineStatus': !prefs.hideOnlineStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).then((_) async {
      final reminderRef = _firestore.doc('mevoraHourReminders/$uid');
      if (prefs.mevoraHourReminders) {
        await reminderRef.set({
          'enabled': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        await reminderRef.set({
          'enabled': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
  }

  @override
  Future<void> registerToken(String uid, String token) {
    return _messaging.registerDevice(uid: uid, token: token);
  }

  @override
  Future<void> unregisterToken(String uid, String token) {
    return _messaging.unregisterDevice(uid: uid, token: token);
  }

  @override
  Future<Result<void>> requestPermission() => _messaging.requestPermission();

  @override
  Future<Result<String?>> getToken() => _messaging.getToken();

  @override
  Stream<AppNotification> watchForeground() => _messaging.watchForeground();

  /// Inbox query is owner-only and paginated. Clients never send FCM.
  Stream<List<AppNotification>> watchInbox(String uid, {int limit = 30}) {
    return _notifications
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
          return [
            for (final doc in snap.docs)
              AppNotification(
                id: doc.id,
                title: (doc.data()['title'] as String?) ?? '',
                body: (doc.data()['body'] as String?) ?? '',
                createdAt: doc.data()['createdAt'] is Timestamp
                    ? (doc.data()['createdAt'] as Timestamp).toDate()
                    : DateTime.fromMillisecondsSinceEpoch(0),
                route: doc.data()['route'] as String?,
                isRead: doc.data()['isRead'] == true,
              ),
          ];
        });
  }

  NotificationPrefs _prefsFrom(Map<String, dynamic> data) {
    return NotificationPrefs(
      messageNotifications: data['messageNotifications'] as bool? ?? true,
      matchNotifications: data['matchNotifications'] as bool? ?? true,
      mevoraHourReminders: data['mevoraHourReminders'] as bool? ?? false,
      hideOnlineStatus: data['showOnlineStatus'] == false,
    );
  }
}
