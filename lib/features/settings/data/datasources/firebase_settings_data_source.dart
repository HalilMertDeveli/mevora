import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/localization/app_language.dart';
import 'package:mevora/features/settings/domain/entities/user_settings.dart';

class FirebaseSettingsDataSource {
  FirebaseSettingsDataSource({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<UserSettings> loadSettings(String uid) async {
    final snap = await _firestore
        .collection(FirestorePaths.userSettings)
        .doc(uid)
        .get();
    final data = snap.data() ?? const <String, dynamic>{};
    return UserSettings(
      uid: uid,
      languageCode: AppLanguage.fromCode(
        (data['languageCode'] as String?) ?? (data['language'] as String?),
      ).code,
      theme: (data['theme'] as String?) ?? 'system',
      notificationsEnabled: data['notificationsEnabled'] as bool? ?? true,
      messageNotifications: data['messageNotifications'] as bool? ?? true,
      matchNotifications: data['matchNotifications'] as bool? ?? true,
      superLikeNotifications: data['superLikeNotifications'] as bool? ?? true,
      callNotifications: data['callNotifications'] as bool? ?? true,
      locationEnabled: data['locationEnabled'] as bool? ?? false,
      locationOnboardingCompleted:
          data['locationOnboardingCompleted'] as bool? ?? false,
      lastLocationUpdate: firestoreDate(data['lastLocationUpdate']),
      showOnlineStatus: data['showOnlineStatus'] as bool? ?? true,
    );
  }

  Future<void> saveSettings(UserSettings settings) {
    return _firestore.collection(FirestorePaths.userSettings).doc(settings.uid).set({
      'languageCode': settings.languageCode,
      'language': settings.languageCode,
      'theme': settings.theme,
      'notificationsEnabled': settings.notificationsEnabled,
      'messageNotifications': settings.messageNotifications,
      'matchNotifications': settings.matchNotifications,
      'superLikeNotifications': settings.superLikeNotifications,
      'callNotifications': settings.callNotifications,
      'locationEnabled': settings.locationEnabled,
      'locationOnboardingCompleted': settings.locationOnboardingCompleted,
      if (settings.lastLocationUpdate case final lastLocationUpdate?)
        'lastLocationUpdate': Timestamp.fromDate(lastLocationUpdate),
      'showOnlineStatus': settings.showOnlineStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<UserPrivacy> loadPrivacy(String uid) async {
    final snap = await _firestore
        .collection(FirestorePaths.userPrivacy)
        .doc(uid)
        .get();
    final data = snap.data() ?? const <String, dynamic>{};
    return UserPrivacy(
      uid: uid,
      showOnlineStatus: data['showOnlineStatus'] as bool? ?? true,
      showDistance: data['showDistance'] as bool? ?? true,
      showAge: data['showAge'] as bool? ?? true,
      showActivity: data['showActivity'] as bool? ?? true,
      allowNotifications: data['allowNotifications'] as bool? ?? true,
      allowCalls: data['allowCalls'] as bool? ?? true,
      allowMessages: data['allowMessages'] as bool? ?? true,
    );
  }

  Future<void> savePrivacy(UserPrivacy privacy) {
    return _firestore.collection(FirestorePaths.userPrivacy).doc(privacy.uid).set({
      'showOnlineStatus': privacy.showOnlineStatus,
      'showDistance': privacy.showDistance,
      'showAge': privacy.showAge,
      'showActivity': privacy.showActivity,
      'allowNotifications': privacy.allowNotifications,
      'allowCalls': privacy.allowCalls,
      'allowMessages': privacy.allowMessages,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
