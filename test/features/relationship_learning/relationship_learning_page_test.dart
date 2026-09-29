import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/relationship_learning_scope.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/relationship_learning/domain/entities/relationship_learning.dart';
import 'package:mevora/features/relationship_learning/presentation/controllers/learning_journey_controller.dart';
import 'package:mevora/features/relationship_learning/presentation/pages/relationship_learning_page.dart';
import 'package:mevora/features/settings/presentation/widgets/personalization_setting_tile.dart';
import 'package:mevora/l10n/app_localizations.dart';

import 'learning_fakes.dart';

final _tr = lookupAppLocalizations(const Locale('tr'));

Widget _app(
  Widget home,
  FakeRelationshipLearningRepository repository, {
  double textScale = 1.0,
  LearningJourneyController? journey,
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
      child: RelationshipLearningScope(
        repository: repository,
        journey: journey,
        child: child!,
      ),
    ),
    home: home,
  );
}

void main() {
  testWidgets("introduces today's 10 without diagnosis wording", (
    tester,
  ) async {
    final repository = FakeRelationshipLearningRepository();
    await tester.pumpWidget(_app(const RelationshipLearningPage(), repository));
    await tester.pumpAndSettle();
    expect(find.text('Mevora seni her gün biraz daha tanısın'), findsOneWidget);
    expect(
      find.text(
        'Bugünün 10 kısa sorusu, sana daha uygun kişileri seçmemize '
        'yardımcı olacak.',
      ),
      findsOneWidget,
    );
    expect(find.text(_tr.learningIntroMeta(10)), findsOneWidget);
    await tester.tap(find.byKey(const Key('learningStartButton')));
    await tester.pumpAndSettle();
    expect(find.text('1 / 10'), findsOneWidget);
    expect(find.text('Soru 1?'), findsOneWidget);
  });

  testWidgets('resumes at question 5 with 5 / 10 progress', (tester) async {
    final repository = FakeRelationshipLearningRepository(answered: 4);
    await tester.pumpWidget(_app(const RelationshipLearningPage(), repository));
    await tester.pumpAndSettle();
    expect(find.text('5 / 10'), findsOneWidget);
    expect(find.text('Soru 5?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('learningOption_b')));
    await tester.pumpAndSettle();
    expect(repository.saves.single.$2, 'relationship_q5_v1');
    expect(find.text('6 / 10'), findsOneWidget);

    await tester.tap(find.byKey(const Key('learningPreviousButton')));
    await tester.pumpAndSettle();
    expect(find.text('Soru 5?'), findsOneWidget);
  });

  testWidgets('finishing question 10 says "Bugünlük tamam."', (tester) async {
    final repository = FakeRelationshipLearningRepository(answered: 9);
    await tester.pumpWidget(_app(const RelationshipLearningPage(), repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('learningOption_a')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Bugünlük tamam.'), findsOneWidget);
    expect(
      find.textContaining('Mevora artık seni biraz daha iyi tanıyor.'),
      findsOneWidget,
    );
    expect(repository.completions, 1);
  });

  testWidgets('a completed day is not shown again', (tester) async {
    final repository = FakeRelationshipLearningRepository(answered: 10);
    await tester.pumpWidget(_app(const RelationshipLearningPage(), repository));
    await tester.pumpAndSettle();
    expect(find.text('Bugünlük tamam.'), findsOneWidget);
    expect(find.byKey(const Key('learningOption_a')), findsNothing);
    expect(find.byKey(const Key('learningSkipTodayButton')), findsNothing);
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

  testWidgets('"Bugünlük geç" puts today away and says so', (tester) async {
    final repository = FakeRelationshipLearningRepository(answered: 3);
    await tester.pumpWidget(_app(const RelationshipLearningPage(), repository));
    await tester.pumpAndSettle();
    expect(find.text('Bugünlük geç'), findsOneWidget);
    await tester.tap(find.byKey(const Key('learningSkipTodayButton')));
    await tester.pumpAndSettle();
    expect(repository.skips, 1);
    expect(find.text(_tr.learningSkippedTitle), findsOneWidget);
  });

  testWidgets("a new member's first set offers no skip and no way around it", (
    tester,
  ) async {
    final repository = FakeRelationshipLearningRepository(required: true);
    final journey = LearningJourneyController(
      repository: repository,
      humorEnabled: false,
    );
    addTearDown(journey.dispose);
    await journey.refresh();
    await tester.pumpWidget(
      _app(
        const RelationshipLearningPage(source: 'journey'),
        repository,
        journey: journey,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('learningSkipTodayButton')), findsNothing);
    expect(find.byKey(const Key('learningCloseButton')), findsNothing);
  });

  testWidgets('closing the journey step skips today for an existing member', (
    tester,
  ) async {
    final repository = FakeRelationshipLearningRepository(answered: 1);
    final journey = LearningJourneyController(
      repository: repository,
      humorEnabled: false,
    );
    addTearDown(journey.dispose);
    await journey.refresh();
    expect(journey.stage, JourneyStage.daily);
    await tester.pumpWidget(
      _app(
        const RelationshipLearningPage(source: 'journey'),
        repository,
        journey: journey,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('learningCloseButton')));
    await tester.pumpAndSettle();
    expect(repository.skips, 1);
    expect(journey.stage, JourneyStage.done, reason: 'never trapped');
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

  test('route locations carry next and source', () {
    expect(RelationshipLearningPage.location(), '/relationship-learning');
    final uri = Uri.parse(
      RelationshipLearningPage.location(next: '/discovery', source: 'picks'),
    );
    expect(uri.queryParameters['next'], '/discovery');
    expect(uri.queryParameters['source'], 'picks');
    expect(uri.queryParameters.containsKey('mode'), isFalse);
  });

  group('reset what Mevora learned', () {
    testWidgets('asks first, then resets on the server only', (tester) async {
      final repository = FakeRelationshipLearningRepository(answered: 10);
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
      expect(repository.answeredToday, 10, reason: 'answers are kept');
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
