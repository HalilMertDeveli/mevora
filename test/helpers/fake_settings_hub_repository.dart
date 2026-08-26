import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/settings/domain/entities/blocked_user_entry.dart';
import 'package:mevora/features/settings/domain/entities/user_settings.dart';
import 'package:mevora/features/settings/domain/repositories/settings_hub_repository.dart';

class FakeSettingsHubRepository implements SettingsHubRepository {
  UserProfile? profile;
  UserPreferences? preferences;
  UserSettings? settings;
  UserPrivacy? privacy;
  List<BlockedUserEntry> blocked = const [];

  @override
  Future<UserProfile?> loadProfile(String uid) async => profile;

  @override
  Stream<UserProfile?> watchProfile(String uid) async* {
    yield profile;
  }

  @override
  Future<void> saveProfile(UserProfile next) async {
    profile = next;
  }

  @override
  Future<UserPreferences> loadDiscoveryPreferences(String uid) async {
    return preferences ?? UserPreferences(uid: uid);
  }

  @override
  Future<void> saveDiscoveryPreferences(UserPreferences next) async {
    preferences = next;
  }

  @override
  Future<UserSettings> loadSettings(String uid) async {
    return settings ?? UserSettings(uid: uid);
  }

  @override
  Stream<UserSettings> watchSettings(String uid) async* {
    yield settings ?? UserSettings(uid: uid);
  }

  @override
  Future<void> saveSettings(UserSettings next) async {
    settings = next;
  }

  @override
  Future<UserPrivacy> loadPrivacy(String uid) async {
    return privacy ?? UserPrivacy(uid: uid);
  }

  @override
  Stream<UserPrivacy> watchPrivacy(String uid) async* {
    yield privacy ?? UserPrivacy(uid: uid);
  }

  @override
  Future<void> savePrivacy(UserPrivacy next) async {
    privacy = next;
  }

  @override
  Stream<List<BlockedUserEntry>> watchBlockedUsers(String uid) async* {
    yield blocked;
  }

  @override
  Future<void> unblockUser({
    required String uid,
    required String blockedUserId,
  }) async {
    blocked = blocked.where((entry) => entry.userId != blockedUserId).toList();
  }
}
