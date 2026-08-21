import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/matching/domain/match_engine.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/swipe_action.dart';
import 'package:mevora/features/relationship/domain/config/relationship_question_config.dart';
import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';
import 'package:mevora/features/relationship/data/datasources/mock_relationship_data_source.dart';
import 'package:mevora/features/relationship/data/repositories/relationship_repository_impl.dart';
import 'package:mevora/features/relationship/domain/services/relationship_compatibility.dart';
import 'package:mevora/features/relationship/domain/services/relationship_match_rules.dart';

void main() {
  test('catalog has at least 100 unique questions with three answers', () {
    final ids = RelationshipQuestionCatalog.questions
        .map((item) => item.id)
        .toSet();
    expect(
      RelationshipQuestionCatalog.questions.length,
      greaterThanOrEqualTo(100),
    );
    expect(ids.length, RelationshipQuestionCatalog.questions.length);
    for (final question in RelationshipQuestionCatalog.questions) {
      expect(question.answers.length, 3);
      expect(question.answers.map((item) => item.id).toSet().length, 3);
    }
  });

  test('same answers raise compatibility; different answers do not align', () {
    const viewer = {'rq_001': 'a', 'rq_002': 'b', 'rq_005': 'a'};
    const same = {'rq_001': 'a', 'rq_002': 'b', 'rq_007': 'c'};
    const different = {'rq_001': 'b', 'rq_002': 'a'};
    final aligned = RelationshipCompatibilityCalculator.score(
      viewerAnswers: viewer,
      candidateAnswers: same,
    );
    final split = RelationshipCompatibilityCalculator.score(
      viewerAnswers: viewer,
      candidateAnswers: different,
    );
    expect(aligned.sharedQuestionCount, 2);
    expect(aligned.alignedCount, 2);
    expect(aligned.score, 100);
    expect(split.sharedQuestionCount, 2);
    expect(split.alignedCount, 0);
    expect(split.score, 0);
  });

  test('relationship suggestion is not an automatic mutual match', () {
    expect(
      MatchEngine.shouldCreateMatch(
        forward: MatchEngine.buildLike(
          fromUserId: 'a',
          toUserId: 'b',
          action: SwipeAction.like,
          createdAt: DateTime(2026),
        ),
        reverse: null,
        blocked: false,
        existingActiveMatch: false,
      ),
      isFalse,
    );
    expect(
      RelationshipMatchRules.isEligible(
        selfUid: 'self',
        candidateUid: 'rel-ada',
        blocked: const {},
        passed: const {},
        alignedCount: 1,
      ),
      isTrue,
    );
    expect(
      RelationshipMatchRules.isEligible(
        selfUid: 'self',
        candidateUid: 'self',
        blocked: const {},
        passed: const {},
        alignedCount: 3,
      ),
      isFalse,
    );
  });

  test('inactive relationship profiles are not suggested', () async {
    final now = DateTime.utc(2026, 8, 21);
    final source = MockRelationshipDataSource(
      clock: () => now,
      answers: const {'rq_001': 'a', 'rq_002': 'b', 'rq_003': 'c'},
      lastActiveAtByUid: {
        'rel-ada': now.subtract(const Duration(days: 100)),
        'rel-leo': now,
      },
    );
    final result = await source.completeTest(
      questionIds: const ['rq_001', 'rq_002', 'rq_003'],
    );
    expect(result.map((item) => item.candidate.uid), ['rel-leo']);
  });

  test('partial answer overlap is not an exact relationship match', () async {
    final source = MockRelationshipDataSource(
      answers: const {'rq_001': 'a', 'rq_002': 'b', 'rq_003': 'c'},
      peers: [
        const MockRelationshipPeer(
          candidate: DiscoveryCandidate(
            uid: 'rel-mia',
            displayName: 'Mia',
            age: 26,
            photos: [],
            gender: 'woman',
            isDemo: true,
          ),
          answers: {'rq_001': 'a', 'rq_002': 'b', 'rq_003': 'a'},
        ),
      ],
    );
    final result = await source.completeTest(
      questionIds: const ['rq_001', 'rq_002', 'rq_003'],
    );
    expect(result, isEmpty);
  });

  test('no answers means an empty suggestion list, not a match', () async {
    final repository = RelationshipRepositoryImpl(
      dataSource: MockRelationshipDataSource(),
    );
    final result = await repository.getSuggestions();
    expect(result.isSuccess, isTrue);
    expect(result.valueOrNull, isEmpty);
  });

  test('completeTest matches only the nearest person within 100 km', () async {
    final source = MockRelationshipDataSource(
      answers: const {'rq_001': 'a', 'rq_002': 'b', 'rq_003': 'c'},
    );
    final result = await source.completeTest(
      questionIds: const ['rq_001', 'rq_002', 'rq_003'],
    );
    expect(result.map((item) => item.candidate.uid), ['rel-ada']);
    expect(result.first.candidate.distanceKm, 1.4);
    expect(result.first.matchId, MatchEngine.matchId('self', 'rel-ada'));
  });

  test('candidates beyond 100 km are not matched', () async {
    final source = MockRelationshipDataSource(
      answers: const {'rq_001': 'a', 'rq_002': 'b', 'rq_003': 'c'},
      peers: const [
        MockRelationshipPeer(
          candidate: DiscoveryCandidate(
            uid: 'rel-far',
            displayName: 'Far',
            age: 28,
            photos: [],
            gender: 'woman',
            distanceKm: 120,
            isDemo: true,
          ),
          answers: {'rq_001': 'a', 'rq_002': 'b', 'rq_003': 'c'},
        ),
      ],
    );
    final result = await source.completeTest(
      questionIds: const ['rq_001', 'rq_002', 'rq_003'],
    );
    expect(result, isEmpty);
    expect(RelationshipQuestionConfig.maxDistanceKm, 100);
  });

  test('the same answer letters on a different set do not match', () async {
    final source = MockRelationshipDataSource(
      answers: const {'rq_001': 'a', 'rq_002': 'b', 'rq_003': 'c'},
      peers: const [
        MockRelationshipPeer(
          candidate: DiscoveryCandidate(
            uid: 'rel-set',
            displayName: 'Set',
            age: 26,
            photos: [],
            gender: 'woman',
            distanceKm: 2,
            isDemo: true,
          ),
          answers: {'rq_004': 'a', 'rq_005': 'b', 'rq_006': 'c'},
        ),
      ],
    );
    final result = await source.completeTest(
      questionIds: const ['rq_001', 'rq_002', 'rq_003'],
    );
    expect(result, isEmpty);
  });

  test('legacy matches without source count as mutual likes', () {
    final like = Match(
      id: 'a_b',
      userIds: const ['a', 'b'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      isActive: true,
    );
    final testMatch = Match(
      id: 'a_c',
      userIds: const ['a', 'c'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      isActive: true,
      source: MatchSource.relationshipTest,
    );
    expect(like.isRelationshipTest, isFalse);
    expect(testMatch.isRelationshipTest, isTrue);
    expect(matchSourceFrom(null), MatchSource.mutualLike);
    expect(matchSourceFrom('relationship_test'), MatchSource.relationshipTest);
    expect(
      matchSourceFrom(null, matchType: 'relationship'),
      MatchSource.relationshipTest,
    );
  });

  test('the same question cannot be answered twice', () async {
    final source = MockRelationshipDataSource();
    final first = await source.saveAnswer(questionId: 'rq_001', answerId: 'a');
    final second = await source.saveAnswer(questionId: 'rq_001', answerId: 'b');
    expect(first.answerCount, 1);
    expect(second.answerCount, 1);
    expect(second.answeredIds, {'rq_001'});
  });
}
