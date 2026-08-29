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

  test('old match without snapshots stays null-safe (no fake 0%)', () {
    final match = Match(
      id: 'old_a_b',
      userIds: const ['a', 'b'],
      createdAt: DateTime(2025),
      isActive: true,
    );
    expect(match.compatibilitySnapshots, isEmpty);
    expect(match.compatibilityFor('a'), isNull);
    final item = MatchListItem(
      match: match,
      otherUserId: 'b',
      name: 'Legacy',
      compatibility: match.compatibilityFor('a'),
    );
    expect(item.breakdown, isNull);
    expect(item.compatibility, isNull);
  });

  test('race: empty snapshots then merge yields real score', () {
    final early = Match(
      id: 'a_b',
      userIds: const ['a', 'b'],
      createdAt: DateTime(2026),
      isActive: true,
      compatibilitySnapshots: const {},
    );
    expect(early.compatibilityFor('a'), isNull);

    final snap = CompatibilitySnapshot.fromMap({
      'compatibilityScore': 87,
      'compatibilityBreakdown': {
        'overallScore': 87,
        'relationshipScore': 90,
        'interestScore': 80,
        'lifestyleScore': 70,
      },
      'sharedInterests': ['travel'],
      'compatibilityReasons': ['Shared interests'],
    })!;
    final afterMerge = early.copyWith(
      compatibilitySnapshots: {'a': snap, 'b': snap},
    );
    expect(afterMerge.compatibilityFor('a')!.score, 87);
    expect(afterMerge.compatibilityFor('b')!.score, 87);
  });

  test('dual perspective: viewer only sees own snapshot key', () {
    final snapA = CompatibilitySnapshot.fromMap({
      'compatibilityScore': 94,
      'compatibilityBreakdown': {
        'overallScore': 94,
        'relationshipScore': 100,
        'interestScore': 90,
        'lifestyleScore': 80,
      },
    })!;
    final snapB = CompatibilitySnapshot.fromMap({
      'compatibilityScore': 71,
      'compatibilityBreakdown': {
        'overallScore': 71,
        'relationshipScore': 60,
        'interestScore': 50,
        'lifestyleScore': 80,
      },
    })!;
    final match = Match(
      id: 'a_b',
      userIds: const ['a', 'b'],
      createdAt: DateTime(2026),
      isActive: true,
      compatibilitySnapshots: {'a': snapA, 'b': snapB},
    );
    expect(match.compatibilityFor('a')!.score, 94);
    expect(match.compatibilityFor('b')!.score, 71);
    // Mapping uses current uid — never the partner key.
    final itemForA = MatchListItem(
      match: match,
      otherUserId: 'b',
      name: 'B',
      compatibility: match.compatibilityFor('a'),
    );
    expect(itemForA.breakdown?.overallScore, 94);
    expect(itemForA.breakdown?.overallScore, isNot(71));
  });

  test('mapFromSnapshotsField ignores absent and zero scores', () {
    final mapped = CompatibilitySnapshot.mapFromSnapshotsField({
      'a': {'compatibilityScore': 0},
      'b': {
        'compatibilityScore': 88,
        'compatibilityBreakdown': {
          'overallScore': 88,
          'relationshipScore': 80,
          'interestScore': 70,
          'lifestyleScore': 60,
        },
      },
    });
    expect(mapped.containsKey('a'), isFalse);
    expect(mapped['b']!.score, 88);
  });
}
