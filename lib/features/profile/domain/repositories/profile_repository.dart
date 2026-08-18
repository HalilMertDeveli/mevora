import 'package:mevora/core/paging/page.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

abstract class ProfileRepository {
  Future<UserProfile?> getById(String uid);

  Stream<UserProfile?> watchById(String uid);

  Future<void> saveMine(UserProfile profile);

  Future<UserPreferences> loadPreferences(String uid);

  Future<void> savePreferences(UserPreferences preferences);

  /// Paginated discovery. Never downloads the whole user set.
  Future<Page<DiscoveryCard>> loadDiscoveryPage({
    String? cursor,
    int limit = 10,
  });
}
