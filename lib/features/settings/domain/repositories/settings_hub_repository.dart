import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/settings/domain/entities/blocked_user_entry.dart';
import 'package:mevora/features/settings/domain/entities/user_settings.dart';

/// Aggregates profile, preferences, settings, privacy, and blocked users.
abstract class SettingsHubRepository {
  Future<UserProfile?> loadProfile(String uid);

  Stream<UserProfile?> watchProfile(String uid);

  Future<void> saveProfile(UserProfile profile);

  /// The member's private surname: stored on their account, never on the
  /// public profile. Null for accounts created before it was collected.
  Future<String?> loadLastName(String uid);

  Future<void> saveLastName(String uid, String lastName);

  /// The member's private date of birth, from their account. It cannot be
  /// changed after onboarding, so there is no save.
  Future<DateTime?> loadBirthDate(String uid);

  Future<UserPreferences> loadDiscoveryPreferences(String uid);

  Future<void> saveDiscoveryPreferences(UserPreferences preferences);

  Future<UserSettings> loadSettings(String uid);

  Stream<UserSettings> watchSettings(String uid);

  Future<void> saveSettings(UserSettings settings);

  Future<UserPrivacy> loadPrivacy(String uid);

  Stream<UserPrivacy> watchPrivacy(String uid);

  Future<void> savePrivacy(UserPrivacy privacy);

  Stream<List<BlockedUserEntry>> watchBlockedUsers(String uid);

  Future<void> unblockUser({required String uid, required String blockedUserId});
}
