import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';
import 'package:mevora/features/relationship/domain/services/relationship_compatibility.dart';
import 'package:mevora/features/relationship/domain/services/relationship_question_sets.dart';

void main() {
  setUp(() {
    RelationshipQuestionCatalog.validateCatalog();
  });

  test('catalog has at least 50 short bilingual questions', () {
    expect(RelationshipQuestionCatalog.questions.length, greaterThanOrEqualTo(50));
    for (final question in RelationshipQuestionCatalog.questions.take(50)) {
      expect(question.promptTr.length, lessThanOrEqualTo(90));
      expect(question.promptEn.length, lessThanOrEqualTo(100));
      expect(question.answers.length, 3);
    }
  });

  test('each question has unique short answers', () {
    for (final question in RelationshipQuestionCatalog.questions) {
      final en = question.answers.map((a) => a.labelEn.trim().toLowerCase()).toSet();
      final tr = question.answers.map((a) => a.labelTr.trim().toLowerCase()).toSet();
      expect(en.length, 3, reason: question.id);
      expect(tr.length, 3, reason: question.id);
      for (final answer in question.answers) {
        expect(answer.labelTr.trim(), isNotEmpty);
        expect(answer.labelEn.trim(), isNotEmpty);
        expect(answer.value.trim(), isNotEmpty);
        expect(answer.labelTr.length, lessThanOrEqualTo(48));
        expect({'a', 'b', 'c'}, contains(answer.id));
      }
    }
  });

  test('answer sets are not copied across questions', () {
    final signatures = <String>{};
    for (final question in RelationshipQuestionCatalog.questions) {
      final signature = question.answers
          .map((a) => '${a.labelEn}|${a.labelTr}')
          .join(';;');
      expect(signatures.add(signature), isTrue, reason: question.id);
    }
  });

  test('no semantic duplicate prompts in catalog', () {
    final keys = <String>{};
    for (final question in RelationshipQuestionCatalog.questions) {
      final key = RelationshipQuestionCatalog.semanticKey(question.promptTr);
      expect(keys.add(key), isTrue, reason: '${question.id} $key');
    }
  });

  test('çay/kahve semantic twins share a key', () {
    expect(
      RelationshipQuestionCatalog.semanticKey('Çay mı kahve mi?'),
      RelationshipQuestionCatalog.semanticKey('Kahve mi çay mı?'),
    );
  });

  test('answered ids block repeats and semantic twins', () {
    final tea = RelationshipQuestionCatalog.questions.firstWhere(
      (q) => q.promptTr.contains('Çay'),
    );
    final blocked = RelationshipQuestionCatalog.blockedQuestionIds({tea.id});
    expect(blocked.contains(tea.id), isTrue);
    final unanswered = RelationshipQuestionCatalog.unanswered({tea.id});
    expect(unanswered.any((q) => q.id == tea.id), isFalse);
  });

  test('session picker skips answered questions', () {
    final firstSet = RelationshipQuestionSets.sets.first;
    final next = RelationshipQuestionSets.nextUnanswered(firstSet.toSet());
    expect(next, isNotNull);
    for (final question in next!) {
      expect(firstSet.contains(question.id), isFalse);
    }
  });

  test('category mix exists across first 30 questions', () {
    final categories = RelationshipQuestionCatalog.questions
        .take(30)
        .map((q) => q.category)
        .toSet();
    expect(categories.contains(RelationshipContentCategory.relationship), isTrue);
    expect(categories.contains(RelationshipContentCategory.fun), isTrue);
    expect(categories.contains(RelationshipContentCategory.dailyLife), isTrue);
  });

  test('answer labels never equal bare Sen or Ben pronouns', () {
    for (final question in RelationshipQuestionCatalog.questions) {
      for (final answer in question.answers) {
        final tr = answer.labelTr.trim().toLowerCase();
        final en = answer.labelEn.trim().toLowerCase();
        expect(tr, isNot(anyOf('sen', 'ben')));
        expect(en, isNot(anyOf('you', 'me', 'i')));
      }
    }
  });

  test('matching still uses stable answer ids', () {
    const viewer = {'rq_001': 'a', 'rq_004': 'b'};
    const aligned = {'rq_001': 'a', 'rq_004': 'b'};
    const split = {'rq_001': 'b', 'rq_004': 'a'};

    final match = RelationshipCompatibilityCalculator.score(
      viewerAnswers: viewer,
      candidateAnswers: aligned,
    );
    final mismatch = RelationshipCompatibilityCalculator.score(
      viewerAnswers: viewer,
      candidateAnswers: split,
    );

    expect(match.score, 100);
    expect(mismatch.score, 0);
    expect(RelationshipQuestionCatalog.byId('rq_001')!.optionById('a')!.id, 'a');
  });

  test('turkish characters preserved in prompts', () {
    final sample = RelationshipQuestionCatalog.questions.where(
      (q) => RegExp(r'[çğıöşüÇĞİÖŞÜ]').hasMatch(q.promptTr),
    );
    expect(sample.length, greaterThan(20));
  });
}
