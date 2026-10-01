import 'package:mevora/core/paging/page.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/profile/domain/repositories/profile_repository.dart';

class FakeProfileRepository implements ProfileRepository {
  final Map<String, UserProfile> profiles = {};

  /// Private surnames, kept apart from [profiles] as on the real backend.
  final Map<String, String> lastNames = {};

  /// Private dates of birth, likewise.
  final Map<String, DateTime> birthDates = {};
  final List<DateTime> birthDateSaves = [];
  UserPreferences? preferences;
  Page<DiscoveryCard> discovery = const Page(items: []);

  @override
  Future<UserProfile?> getById(String uid) async => profiles[uid];

  @override
  Stream<UserProfile?> watchById(String uid) async* {
    yield profiles[uid];
  }

  @override
  Future<void> saveMine(UserProfile profile) async {
    profiles[profile.uid] = profile;
  }

  @override
  Future<String?> loadMyLastName(String uid) async => lastNames[uid];

  @override
  Future<void> saveMyLastName(String uid, String lastName) async {
    lastNames[uid] = lastName.trim();
  }

  @override
  Future<DateTime?> loadMyBirthDate(String uid) async => birthDates[uid];

  @override
  Future<void> saveMyBirthDate(String uid, DateTime birthDate) async {
    birthDateSaves.add(birthDate);
    birthDates[uid] = birthDate;
  }

  @override
  Future<UserPreferences> loadPreferences(String uid) async {
    return preferences ?? UserPreferences(uid: uid);
  }

  @override
  Future<void> savePreferences(UserPreferences next) async {
    preferences = next;
  }

  @override
  Future<Page<DiscoveryCard>> loadDiscoveryPage({
    String? cursor,
    int limit = 10,
  }) async {
    return discovery;
  }
}
