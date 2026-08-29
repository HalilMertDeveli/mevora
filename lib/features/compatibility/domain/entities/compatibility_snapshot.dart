import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';

/// One viewer's persisted compatibility snapshot from a match or likes payload.
class CompatibilitySnapshot {
  const CompatibilitySnapshot({
    required this.score,
    required this.breakdown,
    this.sharedInterests = const [],
    this.reasons = const [],
  });

  final int score;
  final CompatibilityBreakdown breakdown;
  final List<String> sharedInterests;
  final List<String> reasons;

  static CompatibilitySnapshot? fromMap(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final map = Map<String, dynamic>.from(raw);
    final breakdownRaw = map['compatibilityBreakdown'];
    final breakdownMap = breakdownRaw is Map
        ? Map<String, dynamic>.from(breakdownRaw)
        : const <String, dynamic>{};
    final score = firestoreInt(
      map['compatibilityScore'] ?? breakdownMap['overallScore'],
      0,
    );
    if (score <= 0) {
      return null;
    }
    final reasons = firestoreStringList(
      map['compatibilityReasons'] ?? map['reasons'],
    );
    final shared = firestoreStringList(map['sharedInterests']);
    return CompatibilitySnapshot(
      score: score,
      sharedInterests: shared,
      reasons: reasons,
      breakdown: CompatibilityBreakdown(
        overallScore: score,
        relationshipScore: firestoreInt(breakdownMap['relationshipScore'], 0),
        interestScore: firestoreInt(breakdownMap['interestScore'], 0),
        lifestyleScore: firestoreInt(breakdownMap['lifestyleScore'], 0),
        questionScore: breakdownMap['questionScore'] == null
            ? null
            : firestoreInt(breakdownMap['questionScore'], 0),
        musicScore: breakdownMap['musicScore'] == null
            ? null
            : firestoreInt(breakdownMap['musicScore'], 0),
        communicationScore: breakdownMap['communicationScore'] == null
            ? null
            : firestoreInt(breakdownMap['communicationScore'], 0),
        sharedInterests: shared,
        dataQuality: CompatibilityDataQuality.sufficient,
      ),
    );
  }

  static Map<String, CompatibilitySnapshot> mapFromSnapshotsField(Object? raw) {
    if (raw is! Map) {
      return const {};
    }
    final out = <String, CompatibilitySnapshot>{};
    raw.forEach((key, value) {
      final snap = fromMap(value);
      if (snap != null) {
        out[key.toString()] = snap;
      }
    });
    return out;
  }
}
