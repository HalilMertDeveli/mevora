import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Canonical exact-match key: sorted `questionId:answerId` pairs.
/// Hash is what Firestore stores so raw answers stay off the query field.
abstract final class RelationshipCompatibilityKey {
  static String canonical(Map<String, String> answers) {
    final ids = answers.keys.toList()..sort();
    return ids.map((id) => '$id:${answers[id]}').join('|');
  }

  static String hash(Map<String, String> answers) {
    return sha256.convert(utf8.encode(canonical(answers))).toString();
  }

  static bool isExactTriple({
    required Map<String, String> viewer,
    required Map<String, String> candidate,
    required List<String> questionIds,
  }) {
    if (questionIds.length != 3) {
      return false;
    }
    for (final id in questionIds) {
      final left = viewer[id];
      final right = candidate[id];
      if (left == null || right == null || left != right) {
        return false;
      }
    }
    return true;
  }
}
