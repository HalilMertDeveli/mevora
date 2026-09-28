import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/features/profile/data/datasources/firebase_profile_data_source.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/settings/data/datasources/firebase_settings_data_source.dart';
import 'package:mevora/features/settings/domain/entities/blocked_user_entry.dart';
import 'package:mevora/features/settings/domain/entities/user_settings.dart';
import 'package:mevora/features/settings/domain/repositories/settings_hub_repository.dart';
import 'package:mevora/features/safety/domain/safety_policy.dart';

class SettingsHubRepositoryImpl implements SettingsHubRepository {
  SettingsHubRepositoryImpl({
    required FirebaseProfileDataSource profileDataSource,
    required FirebaseSettingsDataSource settingsDataSource,
    FirebaseFirestore? firestore,
  }) : _profileDataSource = profileDataSource,
       _settingsDataSource = settingsDataSource,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseProfileDataSource _profileDataSource;
  final FirebaseSettingsDataSource _settingsDataSource;
  final FirebaseFirestore _firestore;

  @override
  Future<UserProfile?> loadProfile(String uid) => _profileDataSource.fetch(uid);

  @override
  Stream<UserProfile?> watchProfile(String uid) => _profileDataSource.watch(uid);

  @override
  Future<void> saveProfile(UserProfile profile) => _profileDataSource.save(profile);

  @override
  Future<UserPreferences> loadDiscoveryPreferences(String uid) {
    return _profileDataSource.fetchPreferences(uid);
  }

  @override
  Future<void> saveDiscoveryPreferences(UserPreferences preferences) {
    return _profileDataSource.savePreferences(preferences);
  }

  @override
  Future<UserSettings> loadSettings(String uid) {
    return _settingsDataSource.loadSettings(uid);
  }

  @override
  Stream<UserSettings> watchSettings(String uid) {
    return _firestore
        .collection(FirestorePaths.userSettings)
        .doc(uid)
        .snapshots()
        .asyncMap((_) => _settingsDataSource.loadSettings(uid));
  }

  @override
  Future<void> saveSettings(UserSettings settings) {
    return _settingsDataSource.saveSettings(settings);
  }

  @override
  Future<UserPrivacy> loadPrivacy(String uid) {
    return _settingsDataSource.loadPrivacy(uid);
  }

  @override
  Stream<UserPrivacy> watchPrivacy(String uid) {
    return _firestore
        .collection(FirestorePaths.userPrivacy)
        .doc(uid)
        .snapshots()
        .asyncMap((_) => _settingsDataSource.loadPrivacy(uid));
  }

  @override
  Future<void> savePrivacy(UserPrivacy privacy) {
    return _settingsDataSource.savePrivacy(privacy);
  }

  @override
  Stream<List<BlockedUserEntry>> watchBlockedUsers(String uid) {
    return _firestore
        .collection('${FirestorePaths.users}/$uid/${FirestorePaths.blockedUsers}')
        .snapshots()
        .asyncMap((snap) async {
          final entries = <BlockedUserEntry>[];
          for (final doc in snap.docs) {
            final blockedId = doc.id;
            final profile = await _profileDataSource.fetch(blockedId);
            entries.add(
              BlockedUserEntry(
                userId: blockedId,
                displayName: profile?.displayName ?? blockedId,
                photoUrl: profile?.photos
                    .where((p) => p.isPrimary)
                    .map((p) => p.downloadUrl ?? p.thumbUrl)
                    .whereType<String>()
                    .firstOrNull ??
                    profile?.photos
                        .map((p) => p.downloadUrl ?? p.thumbUrl)
                        .whereType<String>()
                        .firstOrNull,
                blockedAt: firestoreDate(doc.data()['createdAt']),
              ),
            );
          }
          entries.sort((a, b) {
            final aTime = a.blockedAt?.millisecondsSinceEpoch ?? 0;
            final bTime = b.blockedAt?.millisecondsSinceEpoch ?? 0;
            return bTime.compareTo(aTime);
          });
          return entries;
        });
  }

  @override
  Future<void> unblockUser({
    required String uid,
    required String blockedUserId,
  }) async {
    final batch = _firestore.batch();
    batch.delete(_firestore.doc(FirestorePaths.blockedUser(uid, blockedUserId)));
    batch.delete(
      _firestore.doc(
        FirestorePaths.block(
          SafetyPolicy.blockId(blockerId: uid, blockedUserId: blockedUserId),
        ),
      ),
    );
    await batch.commit();
  }
}
