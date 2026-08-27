import 'package:mevora/features/matching_streak/data/datasources/firebase_matching_streak_data_source.dart';
import 'package:mevora/features/matching_streak/domain/entities/matching_streak.dart';
import 'package:mevora/features/matching_streak/domain/repositories/matching_streak_repository.dart';

class MatchingStreakRepositoryImpl implements MatchingStreakRepository {
  MatchingStreakRepositoryImpl(this._source);

  final FirebaseMatchingStreakDataSource _source;

  @override
  Stream<MatchingStreak> watchStreak(String uid) => _source.watchStreak(uid);

  @override
  Future<MatchingStreak> getStreak(String uid) => _source.getStreak(uid);

  @override
  Future<MatchingStreak> refreshFromBackend(String uid) =>
      _source.refreshFromBackend(uid);
}
