import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/matching_streak/domain/entities/matching_streak.dart';
import 'package:mevora/features/matching_streak/domain/services/matching_streak_policy.dart';

class FirebaseMatchingStreakDataSource {
  FirebaseMatchingStreakDataSource({
    required BackendCallable backend,
    FirebaseFirestore? firestore,
  }) : _backend = backend,
       _db = firestore ?? FirebaseFirestore.instance;

  final BackendCallable _backend;
  final FirebaseFirestore _db;

  Stream<MatchingStreak> watchStreak(String uid) {
    return _db
        .doc(FirestorePaths.matchingStreakCurrent(uid))
        .snapshots()
        .map(_fromSnap);
  }

  Future<MatchingStreak> getStreak(String uid) async {
    final snap = await _db.doc(FirestorePaths.matchingStreakCurrent(uid)).get();
    return _fromSnap(snap);
  }

  Future<MatchingStreak> refreshFromBackend(String uid) async {
    final map = await _backend.invoke('getMatchingStreak', {});
    return MatchingStreak(
      currentStreak: firestoreInt(map['currentStreak'], 0),
      longestStreak: firestoreInt(map['longestStreak'], 0),
      lastParticipatedDay: map['lastParticipatedDay'] as String?,
      dailyParticipation: map['dailyParticipation'] == true,
      unlockedRewardIds: _rewardIds(map['unlockedRewardIds']),
    );
  }

  MatchingStreak _fromSnap(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? const <String, dynamic>{};
    final lastDay = data['lastParticipatedDay'] as String?;
    final stored = firestoreInt(data['currentStreak'], 0);
    return MatchingStreak(
      currentStreak: MatchingStreakPolicy.effectiveStreak(
        storedStreak: stored,
        lastParticipatedDay: lastDay,
      ),
      longestStreak: firestoreInt(data['longestStreak'], 0),
      lastParticipatedDay: lastDay,
      dailyParticipation: MatchingStreakPolicy.dailyParticipation(
        lastParticipatedDay: lastDay,
      ),
      unlockedRewardIds: _rewardIds(data['unlockedRewardIds']),
    );
  }

  List<String> _rewardIds(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item != null) item.toString(),
    ];
  }
}
