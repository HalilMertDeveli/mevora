import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/matching/domain/match_engine.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_snapshot.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';

class FirebaseMatchDataSource implements MatchRepository, LikeRepository {
  FirebaseMatchDataSource({
    required AuthUidSource uidSource,
    required BackendCallable backend,
    FirebaseFirestore? firestore,
  }) : _uidSource = uidSource,
       _backend = backend,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final AuthUidSource _uidSource;
  final BackendCallable _backend;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _matches =>
      _firestore.collection(FirestorePaths.matches);

  @override
  Stream<List<MatchListItem>> watchMatches(String uid) {
    return _matches
        .where('userIds', arrayContains: uid)
        .where('isActive', isEqualTo: true)
        .orderBy('lastMessageAt', descending: true)
        .limit(40)
        .snapshots()
        .map((snap) {
          return [
            for (final doc in snap.docs)
              _toListItem(_matchFrom(doc.id, doc.data()), uid),
          ];
        });
  }

  @override
  Future<Match?> getMatch(String matchId) async {
    final snap = await _matches.doc(matchId).get();
    if (!snap.exists) {
      return null;
    }
    return _matchFrom(snap.id, snap.data() ?? const {});
  }

  @override
  Stream<Match?> watchMatch(String matchId) {
    return _matches
        .doc(matchId)
        .snapshots()
        .map((snap) {
          if (!snap.exists) {
            return null;
          }
          return _matchFrom(snap.id, snap.data() ?? const {});
        })
        .handleError((Object error, StackTrace stackTrace) {
          // Missing match docs must not crash discovery profile photo UI.
        });
  }

  @override
  Future<void> markOpened(String matchId, String uid) {
    return _matches.doc(matchId).set({
      'isNewFor.$uid': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<SwipeResultWrapper> recordSwipe({
    required String targetUserId,
    required String action,
  }) async {
    final data = await _backend.invoke('recordSwipe', {
      'targetUserId': targetUserId,
      'action': action,
    });
    Match? match;
    final raw = data['match'];
    if (raw is Map) {
      match = _matchFrom(
        (raw['id'] as String?) ??
            MatchEngine.matchId(
              _uidSource.currentUid ?? '',
              targetUserId,
            ),
        Map<String, dynamic>.from(raw),
      );
    }
    return SwipeResultWrapper(
      matched: data['matched'] == true,
      match: match,
    );
  }

  Match _matchFrom(String id, Map<String, dynamic> data) {
    final userIds = (data['userIds'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    final matchedAt = _date(data['matchedAt']);
    final createdAt =
        _date(data['createdAt']) ?? matchedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return Match(
      id: (data['matchId'] as String?) ?? id,
      userIds: userIds,
      createdAt: createdAt,
      isActive: data['isActive'] as bool? ?? true,
      matchedAt: matchedAt,
      lastMessage: data['lastMessage'] as String?,
      lastMessageAt: _date(data['lastMessageAt']),
      unmatchedBy: data['unmatchedBy'] as String?,
      unmatchedAt: _date(data['unmatchedAt']),
      source: matchSourceFrom(data['source'], matchType: data['matchType']),
      compatibilitySnapshots: CompatibilitySnapshot.mapFromSnapshotsField(
        data['compatibilitySnapshots'],
      ),
    );
  }

  MatchListItem _toListItem(Match match, String uid) {
    return MatchListItem(
      match: match,
      otherUserId: match.otherUserId(uid),
      name: match.otherName(uid),
      photoUrl: match.otherPhoto(uid),
      compatibility: match.compatibilityFor(uid),
    );
  }

  DateTime? _date(Object? value) => firestoreDate(value);
}
