import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/relationship_learning_scope.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/relationship_learning/presentation/controllers/relationship_learning_controller.dart';
import 'package:mevora/features/relationship_learning/presentation/pages/relationship_learning_page.dart';
import 'package:mevora/features/settings/presentation/widgets/personalization_setting_tile.dart';
import 'package:mevora/l10n/app_localizations.dart';

import 'learning_fakes.dart';

final _tr = lookupAppLocalizations(const Locale('tr'));

Widget _app(
  Widget home,
  FakeRelationshipLearningRepository repository, {
  double textScale = 1.0,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('tr'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: RelationshipLearningScope(repository: repository, child: child!),
    ),
    home: home,
  );
}

void main() {
  testWidgets('introduces the questions without diagnosis wording', (
    tester,
  ) async {
    final repository = FakeRelationshipLearningRepository();
    await tester.pumpWidget(_app(const RelationshipLearningPage(), repository));
    await tester.pumpAndSettle();
    expect(find.text(_tr.learningIntroTitle), findsOneWidget);
    expect(find.text(_tr.learningIntroBody), findsOneWidget);
    expect(find.text(_tr.learningIntroMeta(15)), findsOneWidget);
    await tester.tap(find.byKey(const Key('learningStartButton')));
    await tester.pumpAndSettle();
    expect(find.text(_tr.learningProgress(1, 15)), findsOneWidget);
    expect(find.text('Soru 1?'), findsOneWidget);
  });

  testWidgets('resumes at question 9 with 4 / 15 style progress', (
    tester,
  ) async {
    final repository = FakeRelationshipLearningRepository(answered: 8);
    await tester.pumpWidget(_app(const RelationshipLearningPage(), repository));
    await tester.pumpAndSettle();
    expect(find.text(_tr.learningProgress(9, 15)), findsOneWidget);
    expect(find.text('Soru 9?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('learningOption_b')));
    await tester.pumpAndSettle();
    expect(repository.saves, [('rl_q9', 'b')]);
    expect(find.text(_tr.learningProgress(10, 15)), findsOneWidget);

    await tester.tap(find.byKey(const Key('learningPreviousButton')));
    await tester.pumpAndSettle();
    expect(find.text('Soru 9?'), findsOneWidget);
  });

  testWidgets('finishing the last question shows the completion screen', (
    tester,
  ) async {
    final repository = FakeRelationshipLearningRepository(answered: 14);
    await tester.pumpWidget(_app(const RelationshipLearningPage(), repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('learningOption_a')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(_tr.learningDoneTitle), findsOneWidget);
    expect(repository.completions, 1);
  });

  testWidgets('a failed save says so and keeps the question', (tester) async {
    final repository = FakeRelationshipLearningRepository(answered: 2)
      ..failSaves = true;
    await tester.pumpWidget(_app(const RelationshipLearningPage(), repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('learningOption_a')));
    await tester.pumpAndSettle();
    expect(find.text(_tr.learningSaveFailed), findsOneWidget);
    expect(find.text('Soru 3?'), findsOneWidget);
  });

  testWidgets('long answers at large text fit a small phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeRelationshipLearningRepository(answered: 3);
    await tester.pumpWidget(
      _app(const RelationshipLearningPage(), repository, textScale: 1.4),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a follow-up round goes straight to its questions', (
    tester,
  ) async {
    final repository = FakeRelationshipLearningRepository(
      answered: 15,
      followUp: [learningQuestion(40), learningQuestion(41)],
    );
    await tester.pumpWidget(
      _app(
        const RelationshipLearningPage(mode: LearningFlowMode.followUp),
        repository,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(_tr.learningProgress(1, 2)), findsOneWidget);
    expect(find.text('Soru 40?'), findsOneWidget);
  });

  testWidgets('route locations carry mode, next and source', (tester) async {
    expect(RelationshipLearningPage.location(), '/relationship-learning');
    final followUp = Uri.parse(
      RelationshipLearningPage.location(
        mode: LearningFlowMode.followUp,
        next: '/discovery',
        source: 'picks',
      ),
    );
    expect(
      learningModeFromQuery(followUp.queryParameters['mode']),
      LearningFlowMode.followUp,
    );
    expect(followUp.queryParameters['next'], '/discovery');
    expect(learningModeFromQuery('nonsense'), LearningFlowMode.initial);
  });

  group('reset what Mevora learned', () {
    testWidgets('asks first, then resets on the server only', (tester) async {
      final repository = FakeRelationshipLearningRepository(answered: 15);
      await tester.pumpWidget(
        _app(const Scaffold(body: PersonalizationResetTile()), repository),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('resetLearnedPersonalizationTile')),
      );
      await tester.pumpAndSettle();
      expect(find.text(_tr.settingsResetLearnedConfirmTitle), findsOneWidget);
      await tester.tap(find.text(_tr.cancel));
      await tester.pumpAndSettle();
      expect(repository.resets, 0);

      await tester.tap(
        find.byKey(const Key('resetLearnedPersonalizationTile')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(_tr.settingsResetLearnedConfirm));
      await tester.pumpAndSettle();
      expect(repository.resets, 1);
      expect(find.text(_tr.settingsResetLearnedDone), findsOneWidget);
      expect(repository.answeredInitial, 15, reason: 'answers are kept');
    });

    testWidgets('reports a failed reset', (tester) async {
      final repository = FakeRelationshipLearningRepository()..failReset = true;
      await tester.pumpWidget(
        _app(const Scaffold(body: PersonalizationResetTile()), repository),
      );
      await tester.tap(
        find.byKey(const Key('resetLearnedPersonalizationTile')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(_tr.settingsResetLearnedConfirm));
      await tester.pumpAndSettle();
      expect(find.text(_tr.settingsResetLearnedFailed), findsOneWidget);
    });
  });
}
