import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/relationship_learning/presentation/controllers/relationship_learning_controller.dart';

import 'learning_fakes.dart';

void main() {
  RelationshipLearningController controllerFor(
    FakeRelationshipLearningRepository repository, {
    LearningFlowMode mode = LearningFlowMode.initial,
  }) {
    final controller = RelationshipLearningController(
      repository: repository,
      mode: mode,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  group('initial questions', () {
    test(
      'a fresh member starts with the introduction, then question 1',
      () async {
        final repository = FakeRelationshipLearningRepository();
        final c = controllerFor(repository);
        await c.load();
        expect(c.phase, LearningFlowPhase.intro);
        expect(c.total, 15);
        c.begin();
        expect(c.phase, LearningFlowPhase.question);
        expect(c.index, 0);
      },
    );

    test('a restart after question 8 resumes at question 9', () async {
      final repository = FakeRelationshipLearningRepository(answered: 8);
      final c = controllerFor(repository);
      await c.load();
      expect(c.phase, LearningFlowPhase.question);
      expect(c.index, 8);
      expect(c.answeredCount, 8);
    });

    test('each answer is saved at once and moves on', () async {
      final repository = FakeRelationshipLearningRepository();
      final c = controllerFor(repository)..begin();
      await c.load();
      c.begin();
      await c.choose('b');
      expect(repository.saves, [('rl_q1', 'b')]);
      expect(c.index, 1);
      expect(c.questions.first.answerId, 'b');
    });

    test('completes once, after the last question', () async {
      final repository = FakeRelationshipLearningRepository(answered: 14);
      final c = controllerFor(repository);
      await c.load();
      expect(c.index, 14);
      await c.choose('a');
      expect(c.phase, LearningFlowPhase.done);
      expect(c.completedInitialNow, isTrue);
      expect(repository.completions, 1);
    });

    test('a member who already finished is not asked again', () async {
      final repository = FakeRelationshipLearningRepository(answered: 15);
      final c = controllerFor(repository);
      await c.load();
      expect(c.phase, LearningFlowPhase.done);
      expect(repository.saves, isEmpty);
    });

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
      expect(repository.saves, [('rl_q1', 'a')]);
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
        expect(repository.saves, [('rl_q4', 'c')]);
        expect(c.index, 4, reason: 'steps forward through answered questions');
        expect(repository.answeredInitial, 5);
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

  group('follow-up rounds', () {
    test('walks the round and finishes it', () async {
      final repository = FakeRelationshipLearningRepository(
        answered: 15,
        followUp: [
          learningQuestion(21, dimension: 'humor'),
          learningQuestion(22, dimension: 'music'),
          learningQuestion(23, dimension: 'values'),
        ],
      );
      final c = controllerFor(repository, mode: LearningFlowMode.followUp);
      await c.load();
      expect(
        c.phase,
        LearningFlowPhase.question,
        reason: 'no intro for a round',
      );
      expect(c.total, 3);
      for (var i = 0; i < 3; i++) {
        await c.choose('a');
      }
      expect(c.phase, LearningFlowPhase.done);
      expect(repository.saves.map((s) => s.$1), ['rl_q21', 'rl_q22', 'rl_q23']);
    });

    test('says so when there is nothing new to ask', () async {
      final repository = FakeRelationshipLearningRepository(answered: 15);
      final c = controllerFor(repository, mode: LearningFlowMode.followUp);
      await c.load();
      expect(c.phase, LearningFlowPhase.nothingToAsk);
    });

    test('auto picks the initial set while unfinished, else a round', () async {
      final unfinished = controllerFor(
        FakeRelationshipLearningRepository(answered: 2),
        mode: LearningFlowMode.auto,
      );
      await unfinished.load();
      expect(unfinished.mode, LearningFlowMode.initial);
      expect(unfinished.index, 2);

      final finished = controllerFor(
        FakeRelationshipLearningRepository(
          answered: 15,
          followUp: [learningQuestion(30)],
        ),
        mode: LearningFlowMode.auto,
      );
      await finished.load();
      expect(finished.mode, LearningFlowMode.followUp);
      expect(finished.total, 1);
    });
  });
}
