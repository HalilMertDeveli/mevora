import 'package:mevora/core/paging/page.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

abstract class ProfileRepository {
  Future<UserProfile?> getById(String uid);

  Stream<UserProfile?> watchById(String uid);

  Future<void> saveMine(UserProfile profile);

  /// The signed-in member's private surname. It is stored on their account,
  /// not on the public profile, so it only ever resolves for [uid]'s owner.
  Future<String?> loadMyLastName(String uid);

  Future<void> saveMyLastName(String uid, String lastName);

  /// The signed-in member's private date of birth, stored beside the surname
  /// on their account. Other members only ever see the age derived from it.
  Future<DateTime?> loadMyBirthDate(String uid);

  Future<void> saveMyBirthDate(String uid, DateTime birthDate);

  Future<UserPreferences> loadPreferences(String uid);

  Future<void> savePreferences(UserPreferences preferences);

  /// Paginated discovery. Never downloads the whole user set.
  Future<Page<DiscoveryCard>> loadDiscoveryPage({
    String? cursor,
    int limit = 10,
  });
}
