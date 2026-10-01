import 'package:mevora/core/paging/page.dart';
import 'package:mevora/features/profile/data/datasources/firebase_profile_data_source.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/profile/domain/repositories/profile_repository.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  ProfileRepositoryImpl({required FirebaseProfileDataSource dataSource})
    : _dataSource = dataSource;

  final FirebaseProfileDataSource _dataSource;

  @override
  Future<UserProfile?> getById(String uid) => _dataSource.fetch(uid);

  @override
  Stream<UserProfile?> watchById(String uid) => _dataSource.watch(uid);

  @override
  Future<void> saveMine(UserProfile profile) => _dataSource.save(profile);

  @override
  Future<String?> loadMyLastName(String uid) => _dataSource.fetchLastName(uid);

  @override
  Future<void> saveMyLastName(String uid, String lastName) {
    return _dataSource.saveLastName(uid, lastName);
  }

  @override
  Future<DateTime?> loadMyBirthDate(String uid) => _dataSource.fetchBirthDate(uid);

  @override
  Future<void> saveMyBirthDate(String uid, DateTime birthDate) {
    return _dataSource.saveBirthDate(uid, birthDate);
  }

  @override
  Future<UserPreferences> loadPreferences(String uid) {
    return _dataSource.fetchPreferences(uid);
  }

  @override
  Future<void> savePreferences(UserPreferences preferences) {
    return _dataSource.savePreferences(preferences);
  }

  @override
  Future<Page<DiscoveryCard>> loadDiscoveryPage({
    String? cursor,
    int limit = 10,
  }) {
    return _dataSource.loadDiscoveryPage(cursor: cursor, limit: limit);
  }
}
