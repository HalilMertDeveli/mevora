import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_snapshot.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';

void main() {
  test('CompatibilitySnapshot.fromMap rejects non-positive scores', () {
    expect(CompatibilitySnapshot.fromMap(null), isNull);
    expect(
      CompatibilitySnapshot.fromMap({'compatibilityScore': 0}),
      isNull,
    );
  });

  test('CompatibilitySnapshot.fromMap maps breakdown fields', () {
    final snap = CompatibilitySnapshot.fromMap({
      'compatibilityScore': 94,
      'compatibilityBreakdown': {
        'overallScore': 94,
        'relationshipScore': 96,
        'interestScore': 88,
        'lifestyleScore': 91,
        'musicScore': 80,
        'questionScore': 70,
        'communicationScore': 70,
      },
      'sharedInterests': ['travel'],
      'compatibilityReasons': ['Shared interests'],
    });
    expect(snap, isNotNull);
    expect(snap!.score, 94);
    expect(snap.breakdown.overallScore, 94);
    expect(snap.breakdown.musicScore, 80);
    expect(snap.sharedInterests, ['travel']);
  });

  test('MatchListItem exposes viewer snapshot breakdown', () {
    final snap = CompatibilitySnapshot.fromMap({
      'compatibilityScore': 90,
      'compatibilityBreakdown': {
        'overallScore': 90,
        'relationshipScore': 80,
        'interestScore': 70,
        'lifestyleScore': 60,
      },
    })!;
    final match = Match(
      id: 'a_b',
      userIds: const ['a', 'b'],
      createdAt: DateTime(2026),
      isActive: true,
      compatibilitySnapshots: {'a': snap},
    );
    final item = MatchListItem(
      match: match,
      otherUserId: 'b',
      name: 'Elif',
      compatibility: match.compatibilityFor('a'),
    );
    expect(item.breakdown?.overallScore, 90);
    expect(match.compatibilityFor('b'), isNull);
  });
}
