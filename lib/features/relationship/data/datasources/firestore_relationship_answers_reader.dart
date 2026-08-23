import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mevora/core/constants/firestore_paths.dart';

/// Reads the signed-in user's relationship answers from Firestore (owner read).
class FirestoreRelationshipAnswersReader {
  FirestoreRelationshipAnswersReader({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<Map<String, String>> loadAnswers(String uid) async {
    final summary = await _firestore
        .doc('${FirestorePaths.users}/$uid/relationshipMatch/summary')
        .get();
    final data = summary.data();
    final raw = data?['answers'];
    if (raw is! Map) {
      return const {};
    }
    return raw.map(
      (key, value) => MapEntry('$key', '$value'),
    );
  }
}
