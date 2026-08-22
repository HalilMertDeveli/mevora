import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/match_score/data/datasources/match_score_data_source.dart';
import 'package:mevora/features/match_score/domain/entities/match_score.dart';
import 'package:mevora/features/match_score/domain/services/match_score_policy.dart';

class FirebaseMatchScoreDataSource implements MatchScoreDataSource {
  FirebaseMatchScoreDataSource({
    required BackendCallable backend,
    FirebaseFirestore? firestore,
  }) : _backend = backend,
       _db = firestore ?? FirebaseFirestore.instance;

  final BackendCallable _backend;
  final FirebaseFirestore _db;

  @override
  Stream<MatchScoreSnapshot> watchScore(String uid) {
    return _db.doc(FirestorePaths.user(uid)).snapshots().map(_scoreFrom);
  }

  @override
  Future<MatchScoreSnapshot> getScore(String uid) async {
    final snap = await _db.doc(FirestorePaths.user(uid)).get();
    return _scoreFrom(snap);
  }

  @override
  Stream<List<MatchScoreHistoryEntry>> watchHistory(String uid) {
    return _db
        .collection(FirestorePaths.matchScoreHistory(uid))
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) {
          return snap.docs.map(_historyFrom).toList(growable: false);
        });
  }

  @override
  Stream<List<PendingMatchFeedback>> watchPendingFeedback(String uid) {
    return _db
        .collection(FirestorePaths.pendingMatchFeedback(uid))
        .snapshots()
        .map((snap) {
          return snap.docs.map(_pendingFrom).toList(growable: false);
        })
        .handleError((Object _, StackTrace __) {
          // Owner list can fail briefly after Google sign-in (token / App Check).
        });
  }

  @override
  Future<void> submitFeedback({
    required String uid,
    required String matchId,
    required String text,
  }) {
    return _backend.invoke('submitMatchFeedback', {
      'matchId': matchId,
      'text': text,
    });
  }

  @override
  Future<void> dismissFeedback({
    required String uid,
    required String matchId,
  }) {
    return _backend.invoke('dismissMatchFeedback', {'matchId': matchId});
  }

  MatchScoreSnapshot _scoreFrom(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? const <String, dynamic>{};
    return MatchScoreSnapshot(
      score: firestoreInt(data['matchScore'], MatchScorePolicy.initialScore),
      matchCount: firestoreInt(data['matchCount'], 0),
    );
  }

  MatchScoreHistoryEntry _historyFrom(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final type = data['type'] == 'post_match_interaction'
        ? MatchScoreHistoryType.postMatchInteraction
        : MatchScoreHistoryType.newMatch;
    return MatchScoreHistoryEntry(
      id: doc.id,
      type: type,
      delta: firestoreInt(data['delta'], 1),
      createdAt: firestoreDate(data['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  PendingMatchFeedback _pendingFrom(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return PendingMatchFeedback(
      matchId: (data['matchId'] as String?) ?? doc.id,
      endedBy: (data['endedBy'] as String?) ?? '',
      endedReason: (data['endedReason'] as String?) ?? 'unmatch',
      createdAt: firestoreDate(data['createdAt']),
    );
  }
}
