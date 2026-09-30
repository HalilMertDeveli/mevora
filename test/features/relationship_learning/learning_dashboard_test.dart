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
  testWidgets('shows real counts, categories, read-backs and answers', (
    tester,
  ) async {
    final repository = FakeRelationshipLearningRepository(
      answered: 10,
      earlier: [for (var i = 50; i < 60; i++) learningQuestion(i, answer: 'b')],
    )..thisMonth = 20;
    await tester.pumpWidget(_app(const LearningDashboardPage(), repository));
    await tester.pumpAndSettle();
    expect(find.text(_tr.learningDashboardHeadline), findsOneWidget);
    expect(find.text('Bu ay 30 soru cevapladın'), findsOneWidget);
    expect(find.text(_tr.learningDashboardTotals(20, 1)), findsOneWidget);
    expect(find.byKey(const Key('learningDashboardTodayDone')), findsOneWidget);
    expect(find.text(_tr.learningCategoryRelationship), findsOneWidget);
    expect(find.text(_tr.learningDashboardPercent(13)), findsOneWidget);
    final highlight = find.text('Adım adım ilerlemeye daha yakınsın.');
    await tester.scrollUntilVisible(highlight, 300);
    expect(highlight, findsOneWidget);
    final earlier = find.byKey(const Key('learningAnswer_relationship_q50_v1'));
    await tester.scrollUntilVisible(earlier, 300);
    expect(earlier, findsOneWidget);
  });

  testWidgets("an unfinished day opens today's questions where they stopped", (
    tester,
  ) async {
    final repository = FakeRelationshipLearningRepository(answered: 6);
    await tester.pumpWidget(_app(const LearningDashboardPage(), repository));
    await tester.pumpAndSettle();
    expect(find.text('Bugünün soruları (6/10)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('learningDashboardToday')));
    await tester.pumpAndSettle();
    expect(find.byType(RelationshipLearningPage), findsOneWidget);
    expect(find.text('7 / 10'), findsOneWidget);
  });

  testWidgets('finishing today from the dashboard comes back to it, done', (
    tester,
  ) async {
    final repository = FakeRelationshipLearningRepository(answered: 8);
    await tester.pumpWidget(_app(const LearningDashboardPage(), repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('learningDashboardToday')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('learningOption_a')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Bugünlük tamam.'), findsOneWidget);
    await tester.tap(find.text(_tr.learningDoneContinue));
    await tester.pumpAndSettle();
    expect(find.byType(LearningDashboardPage), findsOneWidget);
    expect(find.byKey(const Key('learningDashboardTodayDone')), findsOneWidget);
  });

  testWidgets('changing an earlier answer updates it and refreshes', (
    tester,
  ) async {
    final repository = FakeRelationshipLearningRepository(
      answered: 10,
      earlier: [learningQuestion(50, answer: 'a')],
    );
    await tester.pumpWidget(_app(const LearningDashboardPage(), repository));
    await tester.pumpAndSettle();
    final row = find.byKey(const Key('learningAnswer_relationship_q50_v1'));
    await tester.scrollUntilVisible(row, 300);
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('learningEditOption_c')));
    await tester.pumpAndSettle();
    expect(repository.updates, [('relationship_q50_v1', 'c')]);
    expect(repository.earlier.single.answerId, 'c');
    expect(repository.saves, isEmpty, reason: 'an edit is not a new answer');
  });

  testWidgets('choosing the same answer again saves nothing', (tester) async {
    final repository = FakeRelationshipLearningRepository(answered: 10);
    await tester.pumpWidget(_app(const LearningDashboardPage(), repository));
    await tester.pumpAndSettle();
    final row = find.byKey(const Key('learningAnswer_relationship_q1_v1'));
    await tester.scrollUntilVisible(row, 300);
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('learningEditOption_a')));
    await tester.pumpAndSettle();
    expect(repository.updates, isEmpty);
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
    "right after the Humor Lab, today's questions open with a transition",
    (tester) async {
      final repository = FakeRelationshipLearningRepository(required: true)
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
      'totals': {'thisMonth': 30, 'total': 120, 'completedDays': 12},
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
          'questionId': 'relationship_pace_v1',
          'category': 'relationship',
          'text': {'tr': 'x', 'en': 'y'},
        },
        {'questionId': 'relationship_bad_v1'},
      ],
      'answered': [
        {
          'id': 'relationship_pace_v1',
          'version': 1,
          'prompt': {'tr': 'Soru?', 'en': 'Question?'},
          'options': [
            {
              'id': 'fast',
              'label': {'tr': 'A', 'en': 'A'},
            },
            {
              'id': 'slow',
              'label': {'tr': 'B', 'en': 'B'},
            },
          ],
          'answerId': 'slow',
          'category': 'relationship',
          'answeredAtMs': 1_700_000_000_000,
        },
        {
          'id': 'relationship_unanswered_v1',
          'prompt': {'tr': 'x', 'en': 'x'},
          'options': <Object>[],
        },
      ],
    });
    expect(overview.overallProgress, 1.0, reason: 'clamped');
    expect(overview.totals.thisMonth, 30);
    expect(overview.totals.total, 120);
    expect(overview.totals.completedDays, 12);
    expect(overview.categories.single.key, 'humor');
    expect(overview.highlights.single.textFor('tr'), 'x');
    expect(overview.answered.single.question.answerId, 'slow');
    expect(overview.answered.single.category, 'relationship');
    expect(overview.answered.single.answeredAt, isNotNull);
    expect(RelationshipLearningParser.parseOverview(null).categories, isEmpty);
  });
}
