import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/humor_scope.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/domain/entities/humor_calibration.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/presentation/controllers/humor_controller.dart';
import 'package:mevora/features/humor/presentation/pages/humor_calibration_intro_page.dart';
import 'package:mevora/features/humor/presentation/pages/humor_lab_page.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/fake_network_images.dart';

Widget _wrap(Widget child, MockHumorDataSource source) {
  return HumorScope(
    repository: HumorRepositoryImpl(dataSource: source),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('tr'),
      home: child,
    ),
  );
}

void main() {
  group('calibration invitation', () {
    testWidgets('offers a start and a skip, and never blocks', (tester) async {
      final source = MockHumorDataSource();
      var exited = false;

      await tester.pumpWidget(
        _wrap(HumorCalibrationIntroPage(onExit: () => exited = true), source),
      );
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('tr'));
      expect(find.text(l10n.humorCalibrationIntroTitle), findsOneWidget);
      expect(find.text(l10n.humorCalibrationIntroMeta), findsOneWidget);
      expect(find.text(l10n.humorCalibrationStart), findsOneWidget);
      // Skip is offered in two places; either must work.
      expect(find.text(l10n.humorCalibrationSkip), findsWidgets);

      await tester.tap(find.text(l10n.humorCalibrationSkip).last);
      await tester.pumpAndSettle();
      expect(exited, isTrue, reason: 'skipping must let the user continue');
    });

    testWidgets('never leaks internal stage vocabulary', (tester) async {
      final source = MockHumorDataSource();
      await tester.pumpWidget(_wrap(const HumorCalibrationIntroPage(), source));
      await tester.pumpAndSettle();

      for (final internal in [
        'anchor',
        'Anchor',
        'adaptive',
        'Adaptive',
        'exploration',
        'Exploration',
        'vector',
        'calibrationVersion',
      ]) {
        expect(
          find.textContaining(internal),
          findsNothing,
          reason: '"$internal" is an internal term and must not reach the user',
        );
      }
    });

    testWidgets('invites a partly calibrated user to continue', (tester) async {
      final source = MockHumorDataSource();
      // Rate a few items so the server reports partial progress.
      for (var i = 0; i < 4; i += 1) {
        await source.submitFeedback(
          contentId: MockHumorDataSource.seedCatalog[i].contentId,
          rating: HumorRating.funny,
        );
      }

      await tester.pumpWidget(_wrap(const HumorCalibrationIntroPage(), source));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('tr'));
      expect(find.text(l10n.humorCalibrationResume), findsOneWidget);
      expect(find.text(l10n.humorCalibrationStart), findsNothing);
      expect(
        find.text(
          l10n.humorCalibrationProgress(4, HumorCalibration.totalInteractions),
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.humorCalibrationResumeNote), findsOneWidget);
    });
  });

  group('calibration progress', () {
    testWidgets('shows N / 15 while calibrating, not the stage', (
      tester,
    ) async {
      await withFakeNetworkImages(() async {
        final source = MockHumorDataSource();
        final controller = HumorController(
          repository: HumorRepositoryImpl(dataSource: source),
        );

        await tester.pumpWidget(
          _wrap(HumorLabPage(controller: controller), source),
        );
        await tester.pump(const Duration(milliseconds: 400));

        final l10n = await AppLocalizations.delegate.load(const Locale('tr'));
        expect(
          find.text(l10n.humorCalibrationProgress(0, 15)),
          findsOneWidget,
          reason: 'the title should be the progress during calibration',
        );
        expect(find.byType(LinearProgressIndicator), findsOneWidget);

        await controller.rate(HumorRating.funny);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text(l10n.humorCalibrationProgress(1, 15)), findsOneWidget);

        // Stage names must never appear in the UI.
        for (final internal in ['anchor', 'adaptive', 'exploration']) {
          expect(find.textContaining(internal), findsNothing);
        }
      });
    });
  });
}
