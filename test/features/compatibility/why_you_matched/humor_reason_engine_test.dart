import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/context/reason_generator_context.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/entities/why_you_matched_category.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/generators/humor_reason_generator.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/humor/humor_answer_comparator.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/humor/humor_answer_comparison.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/humor/humor_reason_calculator.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_compatibility.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';

void main() {
  const viewer = UserProfile(uid: 'viewer', displayName: 'Ada');
  const candidate = UserProfile(uid: 'candidate', displayName: 'Burak');

  late List<RelationshipQuestion> humorQuestions;

  setUpAll(() {
    humorQuestions = RelationshipQuestionCatalog.questions
        .where(HumorAnswerComparator.isHumorQuestion)
        .toList();
    expect(
      humorQuestions.length,
      greaterThanOrEqualTo(5),
      reason: 'catalog must contain humor-tagged questions',
    );
  });

  Map<String, String> answersFor(
    List<RelationshipQuestion> qs,
    String Function(RelationshipQuestion) pick,
  ) {
    return {for (final q in qs) q.id: pick(q)};
  }

  ReasonGeneratorContext ctx({
    Map<String, String> viewerAnswers = const {},
    Map<String, String> candidateAnswers = const {},
    HumorCompatibility? humor,
  }) {
    return ReasonGeneratorContext(
      viewer: viewer,
      candidate: candidate,
      breakdown: const CompatibilityBreakdown(
        overallScore: 70,
        relationshipScore: 70,
        interestScore: 50,
        lifestyleScore: 50,
      ),
      humorAnswerSignals: WhyYouMatchedHumorAnswerSignals(
        viewerAnswers: viewerAnswers,
        candidateAnswers: candidateAnswers,
      ),
      humorCompatibility: humor,
    );
  }

  group('HumorAnswerComparator', () {
    test('1. identical answers → high similarity and score 100', () {
      final qs = humorQuestions.take(5).toList();
      final same = answersFor(qs, (q) => q.answers.first.id);
      final comparison = HumorAnswerComparator.compare(
        viewerAnswers: same,
        candidateAnswers: same,
      );
      expect(comparison.comparableAnswers, 5);
      expect(comparison.matchingAnswers, 5);
      expect(comparison.similarity, 1.0);
      expect(comparison.score, 100);
      expect(HumorAnswerComparator.meetsReasonThreshold(comparison), isTrue);
      expect(HumorAnswerComparator.isStrong(comparison), isTrue);
    });

    test('2. completely different answers → score 0, no reason', () {
      final qs = humorQuestions.take(4).toList();
      final viewerMap = answersFor(qs, (q) => q.answers.first.id);
      final candidateMap = answersFor(qs, (q) => q.answers.last.id);
      final comparison = HumorAnswerComparator.compare(
        viewerAnswers: viewerMap,
        candidateAnswers: candidateMap,
      );
      expect(comparison.comparableAnswers, 4);
      expect(comparison.matchingAnswers, 0);
      expect(comparison.score, 0);
      expect(HumorAnswerComparator.meetsReasonThreshold(comparison), isFalse);
      expect(
        HumorReasonCalculator.fromAnswers(
          candidateUid: 'candidate',
          comparison: comparison,
        ),
        isNull,
      );
    });

    test('3. partial answers → only shared question ids count', () {
      final qs = humorQuestions.take(5).toList();
      final viewerMap = answersFor(qs, (q) => q.answers.first.id);
      final candidateMap = answersFor(
        qs.take(3).toList(),
        (q) => q.answers.first.id,
      );
      final comparison = HumorAnswerComparator.compare(
        viewerAnswers: viewerMap,
        candidateAnswers: candidateMap,
      );
      expect(comparison.comparableAnswers, 3);
      expect(comparison.matchingAnswers, 3);
      expect(comparison.score, 100);
    });

    test('4. missing answers → empty comparison', () {
      final qs = humorQuestions.take(3).toList();
      final viewerMap = answersFor(qs, (q) => q.answers.first.id);
      final comparison = HumorAnswerComparator.compare(
        viewerAnswers: viewerMap,
        candidateAnswers: const {},
      );
      expect(comparison, HumorAnswerComparison.empty);
      expect(HumorAnswerComparator.meetsReasonThreshold(comparison), isFalse);
    });

    test('5. duplicate answers → last answer wins per questionId', () {
      final q = humorQuestions.first;
      final a1 = q.answers.first.id;
      final a2 = q.answers.last.id;
      final normalized = HumorAnswerComparator.normalizeAnswers([
        HumorQuestionAnswer(questionId: q.id, answerId: a1),
        HumorQuestionAnswer(questionId: q.id, answerId: a2),
        HumorQuestionAnswer(questionId: q.id, answerId: a1),
      ]);
      expect(normalized[q.id], a1);
      expect(normalized.length, 1);
    });

    test('6. insufficient data → no strong and no reason', () {
      final qs = humorQuestions.take(1).toList();
      final same = answersFor(qs, (q) => q.answers.first.id);
      final comparison = HumorAnswerComparator.compare(
        viewerAnswers: same,
        candidateAnswers: same,
      );
      expect(comparison.comparableAnswers, 1);
      expect(comparison.matchingAnswers, 1);
      expect(comparison.score, 100);
      expect(HumorAnswerComparator.meetsReasonThreshold(comparison), isFalse);
      expect(HumorAnswerComparator.isStrong(comparison), isFalse);

      // Two comparable but score below threshold (1 of 2 match → 50%)
      final pair = humorQuestions.take(2).toList();
      final viewerMap = answersFor(pair, (q) => q.answers.first.id);
      final candidateMap = {
        pair[0].id: pair[0].answers.first.id,
        pair[1].id: pair[1].answers.last.id,
      };
      final partial = HumorAnswerComparator.compare(
        viewerAnswers: viewerMap,
        candidateAnswers: candidateMap,
      );
      expect(partial.score, 50);
      expect(HumorAnswerComparator.meetsReasonThreshold(partial), isFalse);
    });
  });

  group('HumorReasonGenerator', () {
    const generator = HumorReasonGenerator();

    test('identical answers produce evidence matching N of M', () {
      final qs = humorQuestions.take(5).toList();
      final same = answersFor(qs, (q) => q.answers.first.id);
      // 4 of 5 match
      final candidateMap = Map<String, String>.from(same)
        ..[qs.last.id] = qs.last.answers.last.id;

      final reasons = generator.generate(
        ctx(viewerAnswers: same, candidateAnswers: candidateMap),
      );
      expect(reasons, hasLength(1));
      final reason = reasons.first;
      expect(reason.category, WhyYouMatchedCategory.humor);
      expect(reason.score, 80);
      expect(reason.descriptionArgs, ['4', '5']);
      expect(reason.evidence.type, 'sharedHumorAnswers');
      expect(reason.evidence.values['matching'], 4);
      expect(reason.evidence.values['comparable'], 5);
      expect(reason.strength, WhyYouMatchedStrength.strong);
    });

    test('completely different answers produce no reason', () {
      final qs = humorQuestions.take(4).toList();
      final reasons = generator.generate(
        ctx(
          viewerAnswers: answersFor(qs, (q) => q.answers.first.id),
          candidateAnswers: answersFor(qs, (q) => q.answers.last.id),
        ),
      );
      expect(reasons, isEmpty);
    });

    test('missing answers produce no reason', () {
      expect(generator.generate(ctx()), isEmpty);
    });

    test('duplicate reason not emitted (answers preferred over lab)', () {
      final qs = humorQuestions.take(4).toList();
      final same = answersFor(qs, (q) => q.answers.first.id);
      final reasons = generator.generate(
        ctx(
          viewerAnswers: same,
          candidateAnswers: same,
          humor: const HumorCompatibility(
            available: true,
            score: 90,
            confidence: 0.8,
            strongestShared: [HumorCategory.absurd],
          ),
        ),
      );
      expect(reasons, hasLength(1));
      expect(reasons.first.id, startsWith('humor_answers_'));
    });

    test('Humor Lab fallback when no answers', () {
      final reasons = generator.generate(
        ctx(
          humor: const HumorCompatibility(
            available: true,
            score: 88,
            confidence: 0.5,
            strongestShared: [HumorCategory.sarcasm, HumorCategory.absurd],
          ),
        ),
      );
      expect(reasons, hasLength(1));
      expect(reasons.first.evidence.type, 'humorVectorSimilarity');
      expect(reasons.first.descriptionArgs, ['2', '11']);
    });

    test('score text never contradicts score', () {
      final qs = humorQuestions.take(5).toList();
      final viewerMap = answersFor(qs, (q) => q.answers.first.id);
      final candidateMap = {
        for (var i = 0; i < qs.length; i++)
          qs[i].id: i < 4 ? qs[i].answers.first.id : qs[i].answers.last.id,
      };
      final reason = generator.generate(
        ctx(viewerAnswers: viewerMap, candidateAnswers: candidateMap),
      ).single;
      final matching = int.parse(reason.descriptionArgs[0]);
      final comparable = int.parse(reason.descriptionArgs[1]);
      expect(reason.score, ((matching / comparable) * 100).round());
    });

    test('insufficient sample never yields strong reason', () {
      final qs = humorQuestions.take(2).toList();
      final same = answersFor(qs, (q) => q.answers.first.id);
      final reason = generator.generate(
        ctx(viewerAnswers: same, candidateAnswers: same),
      ).single;
      // score 100 but comparable=2 < strongMinComparable=3
      expect(reason.score, 100);
      expect(reason.strength, WhyYouMatchedStrength.moderate);
    });
  });
}
