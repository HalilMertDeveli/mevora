import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mevora/core/constants/firestore_paths.dart';

/// Reads the signed-in user's relationship answers from Firestore (owner read).
///
/// Prefer [relationshipMatch/summary].answers when present; otherwise fall back
/// to the [relationshipAnswers] collection — matching the Cloud Function
/// [loadAnswers] path so the edit screen never looks "empty" while answers exist.
class FirestoreRelationshipAnswersReader {
  FirestoreRelationshipAnswersReader({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Pure merge used by [loadAnswers] and unit-tested without Firebase.
  static Map<String, String> preferSummaryOrCollection({
    required Map<String, String> summary,
    required Map<String, String> collection,
  }) {
    if (summary.isNotEmpty) {
      return summary;
    }
    return collection;
  }

  Future<Map<String, String>> loadAnswers(String uid) async {
    final fromSummary = await _loadFromSummary(uid);
    final fromCollection = fromSummary.isEmpty
        ? await _loadFromCollection(uid)
        : const <String, String>{};
    return preferSummaryOrCollection(
      summary: fromSummary,
      collection: fromCollection,
    );
  }

  Future<Map<String, String>> _loadFromSummary(String uid) async {
    final summary = await _firestore
        .doc(FirestorePaths.relationshipMatchSummary(uid))
        .get();
    final data = summary.data();
    final raw = data?['answers'];
    if (raw is! Map) {
      return const {};
    }
    final out = <String, String>{};
    raw.forEach((key, value) {
      final questionId = '$key'.trim();
      final answerId = '$value'.trim();
      if (questionId.isNotEmpty && answerId.isNotEmpty) {
        out[questionId] = answerId;
      }
    });
    return out;
  }

  Future<Map<String, String>> _loadFromCollection(String uid) async {
    final snap = await _firestore
        .collection(
          '${FirestorePaths.users}/$uid/${FirestorePaths.relationshipAnswers}',
        )
        .limit(120)
        .get();
    final out = <String, String>{};
    for (final doc in snap.docs) {
      final answerId = doc.data()['answerId'];
      if (answerId is String && answerId.trim().isNotEmpty) {
        out[doc.id] = answerId.trim();
      }
    }
    return out;
  }
}
