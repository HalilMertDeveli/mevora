import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/relationship_learning_scope.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/relationship_learning/data/relationship_learning_repository_impl.dart';
import 'package:mevora/features/relationship_learning/presentation/pages/learning_dashboard_page.dart';
import 'package:mevora/features/relationship_learning/presentation/pages/relationship_learning_page.dart';
import 'package:mevora/l10n/app_localizations.dart';

import 'learning_fakes.dart';

final _tr = lookupAppLocalizations(const Locale('tr'));

Widget _app(Widget home, FakeRelationshipLearningRepository repository) {
  return MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('tr'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    builder: (context, child) =>
        RelationshipLearningScope(repository: repository, child: child!),
    home: home,
  );
}

void main() {
  testWidgets('shows real progress, categories, read-backs and answers', (
    tester,
  ) async {
    final repository = FakeRelationshipLearningRepository(answered: 15);
    await tester.pumpWidget(_app(const LearningDashboardPage(), repository));
    await tester.pumpAndSettle();
    expect(find.text(_tr.learningDashboardHeadline), findsOneWidget);
    expect(find.text(_tr.learningDashboardPercent(100)), findsWidgets);
    expect(find.text(_tr.learningCategoryRelationship), findsOneWidget);
    expect(find.text(_tr.learningCategoryCommunication), findsOneWidget);
    expect(find.text(_tr.learningDashboardPercent(17)), findsOneWidget);
    expect(find.text('Adım adım ilerlemeye daha yakınsın.'), findsOneWidget);
    final firstAnswer = find.byKey(const Key('learningAnswer_rl_q1'));
    await tester.scrollUntilVisible(firstAnswer, 300);
    expect(firstAnswer, findsOneWidget);
  });

  testWidgets('an unfinished member continues the initial questions', (
    tester,
  ) async {
    final repository = FakeRelationshipLearningRepository(answered: 6);
    await tester.pumpWidget(_app(const LearningDashboardPage(), repository));
    await tester.pumpAndSettle();
    expect(
      find.text(_tr.learningDashboardResumeInitial(6, 15)),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('learningDashboardContinue')));
    await tester.pumpAndSettle();
    expect(find.byType(RelationshipLearningPage), findsOneWidget);
    expect(find.text(_tr.learningProgress(7, 15)), findsOneWidget);
  });

  testWidgets('a finished member continues in a short round, then returns', (
    tester,
  ) async {
    final repository = FakeRelationshipLearningRepository(
      answered: 15,
      followUp: [
        learningQuestion(21),
        learningQuestion(22),
        learningQuestion(23),
      ],
    );
    await tester.pumpWidget(_app(const LearningDashboardPage(), repository));
    await tester.pumpAndSettle();
    expect(find.text(_tr.learningDashboardContinue(3)), findsOneWidget);
    await tester.tap(find.byKey(const Key('learningDashboardContinue')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('learningOption_a')));
      await tester.pumpAndSettle();
    }
    expect(find.text(_tr.learningFollowUpDoneTitle), findsOneWidget);
    await tester.tap(find.text(_tr.learningDoneContinue));
    await tester.pumpAndSettle();
    expect(find.byType(LearningDashboardPage), findsOneWidget);
    expect(
      find.byKey(const Key('learningDashboardAllAnswered')),
      findsOneWidget,
    );
  });

  testWidgets('changing an earlier answer saves it and refreshes', (
    tester,
  ) async {
    final repository = FakeRelationshipLearningRepository(answered: 15);
    await tester.pumpWidget(_app(const LearningDashboardPage(), repository));
    await tester.pumpAndSettle();
    final row = find.byKey(const Key('learningAnswer_rl_q3'));
    await tester.scrollUntilVisible(row, 300);
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('learningEditOption_c')));
    await tester.pumpAndSettle();
    expect(repository.saves, [('rl_q3', 'c')]);
    expect(repository.initial[2].answerId, 'c');
    expect(
      repository.answeredInitial,
      15,
      reason: 'an edit is not a new answer',
    );
  });

  testWidgets('choosing the same answer again saves nothing', (tester) async {
    final repository = FakeRelationshipLearningRepository(answered: 15);
    await tester.pumpWidget(_app(const LearningDashboardPage(), repository));
    await tester.pumpAndSettle();
    final row = find.byKey(const Key('learningAnswer_rl_q1'));
    await tester.scrollUntilVisible(row, 300);
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('learningEditOption_a')));
    await tester.pumpAndSettle();
    expect(repository.saves, isEmpty);
  });

  testWidgets('a load failure offers a retry', (tester) async {
    final repository = FakeRelationshipLearningRepository()..failLoads = true;
    await tester.pumpWidget(_app(const LearningDashboardPage(), repository));
    await tester.pumpAndSettle();
    expect(find.text(_tr.learningLoadErrorTitle), findsOneWidget);
    repository.failLoads = false;
    await tester.tap(find.text(_tr.retry));
    await tester.pumpAndSettle();
    expect(find.text(_tr.learningDashboardHeadline), findsOneWidget);
  });

  testWidgets(
    'right after the Humor Lab, the questions open with a transition',
    (tester) async {
      final repository = FakeRelationshipLearningRepository()
        ..humorCalibrated = true;
      await tester.pumpWidget(
        _app(const RelationshipLearningPage(source: 'journey'), repository),
      );
      await tester.pumpAndSettle();
      expect(find.text(_tr.learningAfterHumorTitle), findsOneWidget);
      expect(find.text(_tr.learningAfterHumorBody), findsOneWidget);
    },
  );

  test('parses the overview and drops malformed parts', () {
    final overview = RelationshipLearningParser.parseOverview({
      'overallProgress': 1.7,
      'categories': [
        {
          'key': 'humor',
          'answered': 1,
          'questions': 3,
          'signals': 1,
          'signalsPossible': 1,
          'progress': 0.5,
        },
        {'answered': 9},
      ],
      'highlights': [
        {
          'questionId': 'rl_pace',
          'category': 'relationship',
          'text': {'tr': 'x', 'en': 'y'},
        },
        {'questionId': 'rl_bad'},
      ],
      'answered': [
        {
          'id': 'rl_pace',
          'prompt': {'tr': 'Soru?', 'en': 'Question?'},
          'options': [
            {
              'id': 'a',
              'label': {'tr': 'A', 'en': 'A'},
            },
            {
              'id': 'b',
              'label': {'tr': 'B', 'en': 'B'},
            },
          ],
          'answerId': 'b',
          'category': 'relationship',
          'answeredAtMs': 1_700_000_000_000,
        },
        {
          'id': 'rl_unanswered',
          'prompt': {'tr': 'x', 'en': 'x'},
          'options': <Object>[],
        },
      ],
    });
    expect(overview.overallProgress, 1.0, reason: 'clamped');
    expect(overview.categories.single.key, 'humor');
    expect(overview.highlights.single.textFor('tr'), 'x');
    expect(overview.answered.single.question.answerId, 'b');
    expect(overview.answered.single.answeredAt, isNotNull);
    expect(RelationshipLearningParser.parseOverview(null).categories, isEmpty);
  });
}
