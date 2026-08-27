import 'package:mevora/features/matching_streak/domain/entities/matching_streak.dart';

abstract class MatchingStreakRepository {
  Stream<MatchingStreak> watchStreak(String uid);

  Future<MatchingStreak> getStreak(String uid);

  Future<MatchingStreak> refreshFromBackend(String uid);
}
