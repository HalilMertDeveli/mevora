import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/relationship_learning/presentation/controllers/relationship_learning_controller.dart';

import 'learning_fakes.dart';

void main() {
  RelationshipLearningController controllerFor(
    FakeRelationshipLearningRepository repository,
  ) {
    final controller = RelationshipLearningController(repository: repository);
    addTearDown(controller.dispose);
    return controller;
  }

  group("today's questions", () {
    test('a fresh day starts with the introduction, then question 1', () async {
      final repository = FakeRelationshipLearningRepository();
      final c = controllerFor(repository);
      await c.load();
      expect(c.phase, LearningFlowPhase.intro);
      expect(c.total, 10);
      expect(c.questionSetId, 'daily-2026-09-29-s1');
      c.begin();
      expect(c.phase, LearningFlowPhase.question);
      expect(c.index, 0);
    });

    test('a restart after question 4 resumes at question 5', () async {
      final repository = FakeRelationshipLearningRepository(answered: 4);
      final c = controllerFor(repository);
      await c.load();
      expect(c.phase, LearningFlowPhase.question);
      expect(c.index, 4);
      expect(c.answeredCount, 4);
    });

    test('each answer is saved at once, with set and version', () async {
      final repository = FakeRelationshipLearningRepository();
      final c = controllerFor(repository);
      await c.load();
      c.begin();
      await c.choose('b');
      expect(repository.saves, [
        ('daily-2026-09-29-s1', 'relationship_q1_v1', 1, 'b'),
      ]);
      expect(c.index, 1);
      expect(c.questions.first.answerId, 'b');
    });

    test('completes once, after the tenth question', () async {
      final repository = FakeRelationshipLearningRepository(answered: 9);
      final c = controllerFor(repository);
      await c.load();
      expect(c.index, 9);
      await c.choose('a');
      expect(c.phase, LearningFlowPhase.done);
      expect(c.completedNow, isTrue);
      expect(repository.completions, 1);
    });

    test('a finished day is not asked again', () async {
      final repository = FakeRelationshipLearningRepository(answered: 10);
      final c = controllerFor(repository);
      await c.load();
      expect(c.phase, LearningFlowPhase.done);
      expect(c.completedNow, isFalse);
      expect(repository.saves, isEmpty);
    });

    test('the next day brings a fresh set', () async {
      final repository = FakeRelationshipLearningRepository(answered: 10)
        ..newDay('2026-09-30');
      final c = controllerFor(repository);
      await c.load();
      expect(c.phase, LearningFlowPhase.intro);
      expect(c.questionSetId, 'daily-2026-09-30-s1');
      expect(c.questions.first.id, 'relationship_q101_v1');
    });

    test(
      'an answer sent after midnight reloads today instead of failing',
      () async {
        final repository = FakeRelationshipLearningRepository(answered: 3);
        final c = controllerFor(repository);
        await c.load();
        repository.newDay('2026-09-30');
        await c.choose('a');
        expect(c.takeActionError(), isNull, reason: 'no error snackbar');
        expect(c.questionSetId, 'daily-2026-09-30-s1');
        expect(c.phase, LearningFlowPhase.intro);
        expect(repository.saves, isEmpty);
      },
    );

    test(
      'a failed save keeps the member on the question with their old answer',
      () async {
        final repository = FakeRelationshipLearningRepository(answered: 3)
          ..failSaves = true;
        final c = controllerFor(repository);
        await c.load();
        await c.choose('c');
        expect(c.index, 3);
        expect(c.current!.answerId, isNull);
        expect(c.takeActionError(), isNotNull);
        expect(c.takeActionError(), isNull, reason: 'errors are taken once');
      },
    );

    test('ignores a second tap while an answer is saving', () async {
      final repository = FakeRelationshipLearningRepository();
      final c = controllerFor(repository);
      await c.load();
      c.begin();
      final first = c.choose('a');
      final second = c.choose('b');
      await Future.wait([first, second]);
      expect(repository.saves.map((s) => s.$4), ['a']);
    });

    test('previous and next move through answered questions only', () async {
      final repository = FakeRelationshipLearningRepository(answered: 5);
      final c = controllerFor(repository);
      await c.load();
      expect(c.index, 5);
      expect(c.canGoForward, isFalse, reason: 'the current one is unanswered');
      c.back();
      expect(c.index, 4);
      expect(c.canGoForward, isTrue);
      c.forward();
      expect(c.index, 5);
    });

    test(
      'changing an earlier answer re-saves it without duplicating',
      () async {
        final repository = FakeRelationshipLearningRepository(answered: 5);
        final c = controllerFor(repository);
        await c.load();
        c
          ..back()
          ..back();
        expect(c.index, 3);
        await c.choose('c');
        expect(repository.saves.single.$2, 'relationship_q4_v1');
        expect(c.index, 4, reason: 'steps forward through answered questions');
        expect(repository.answeredToday, 5);
      },
    );

    test('a load failure can be retried', () async {
      final repository = FakeRelationshipLearningRepository()..failLoads = true;
      final c = controllerFor(repository);
      await c.load();
      expect(c.phase, LearningFlowPhase.error);
      repository.failLoads = false;
      await c.load();
      expect(c.phase, LearningFlowPhase.intro);
    });
  });

  group('Bugünlük geç', () {
    test('an existing member can put today away', () async {
      final repository = FakeRelationshipLearningRepository(answered: 2);
      final c = controllerFor(repository);
      await c.load();
      expect(c.canSkip, isTrue);
      expect(await c.skipToday(), isTrue);
      expect(c.phase, LearningFlowPhase.skipped);
      expect(repository.skips, 1);
      expect(repository.answeredToday, 2, reason: 'answers so far are kept');
    });

    test("a new member's first set cannot be skipped", () async {
      final repository = FakeRelationshipLearningRepository(required: true);
      final c = controllerFor(repository);
      await c.load();
      expect(c.canSkip, isFalse);
      expect(await c.skipToday(), isFalse);
      expect(repository.skips, 0);
      expect(c.phase, LearningFlowPhase.intro);
    });

    test('after the first set, the next day can be skipped', () async {
      final repository = FakeRelationshipLearningRepository(
        required: true,
        answered: 10,
      )..newDay('2026-09-30');
      final c = controllerFor(repository);
      await c.load();
      expect(c.canSkip, isTrue);
    });
  });
}
