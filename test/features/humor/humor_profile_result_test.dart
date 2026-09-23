import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/humor_scope.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/user_humor_profile.dart';
import 'package:mevora/features/humor/domain/services/humor_profile_display.dart';
import 'package:mevora/features/humor/presentation/pages/humor_calibration_result_page.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/l10n_harness.dart';

UserHumorProfile _profile(Map<HumorCategory, double> vector) {
  return UserHumorProfile(
    vector: vector,
    interactionCount: 15,
    confidence: 0.35,
    profileBuilding: false,
  );
}

void main() {
  group('strength buckets', () {
    test('map a precise value onto a coarse, honest label', () {
      expect(HumorProfileDisplay.strengthOf(88), HumorStrength.high);
      expect(HumorProfileDisplay.strengthOf(75), HumorStrength.high);
      expect(HumorProfileDisplay.strengthOf(74), HumorStrength.medium);
      expect(HumorProfileDisplay.strengthOf(60), HumorStrength.medium);
      expect(HumorProfileDisplay.strengthOf(59), HumorStrength.low);
      expect(HumorProfileDisplay.strengthOf(0), HumorStrength.low);
    });
  });

  group('summary sentence', () {
    test('is deterministic for the same profile', () {
      final l10n = l10nTr();
      final profile = _profile({
        HumorCategory.sarcasm: 88,
        HumorCategory.absurd: 79,
        HumorCategory.cringe: 20,
      });
      final first = HumorProfileDisplay.summarySentence(l10n, profile);
      final second = HumorProfileDisplay.summarySentence(l10n, profile);
      expect(first, second);
      expect(first, isNotEmpty);
    });

    test('names the two strongest traits and the clear opposite', () {
      final l10n = l10nTr();
      final sentence = HumorProfileDisplay.summarySentence(
        l10n,
        _profile({
          HumorCategory.sarcasm: 88,
          HumorCategory.absurd: 79,
          HumorCategory.cringe: 18,
        }),
      );
      expect(sentence, contains(l10n.humorCategorySarcasm));
      expect(sentence, contains(l10n.humorCategoryAbsurd));
      expect(sentence, contains(l10n.humorCategoryCringe));
    });

    test('does not invent a dislike from a merely neutral dimension', () {
      // 50 means "no evidence", not "dislikes". Claiming otherwise would be
      // inventing a trait the measurement never observed.
      final l10n = l10nTr();
      final sentence = HumorProfileDisplay.summarySentence(
        l10n,
        _profile({
          HumorCategory.sarcasm: 85,
          HumorCategory.absurd: 78,
          HumorCategory.cringe: 50,
          HumorCategory.dry: 50,
        }),
      );
      expect(sentence, isNot(contains(l10n.humorCategoryCringe)));
      expect(sentence, isNot(contains(l10n.humorCategoryDry)));
    });

    test('stays modest when nothing stands out', () {
      final l10n = l10nTr();
      final sentence = HumorProfileDisplay.summarySentence(
        l10n,
        _profile({
          HumorCategory.sarcasm: 52,
          HumorCategory.absurd: 50,
          HumorCategory.meme: 48,
        }),
      );
      expect(sentence, l10n.humorResultSummaryNone);
    });

    test('handles a single strong trait', () {
      final l10n = l10nTr();
      final sentence = HumorProfileDisplay.summarySentence(
        l10n,
        _profile({HumorCategory.wordplay: 90, HumorCategory.meme: 52}),
      );
      expect(sentence, contains(l10n.humorCategoryWordplay));
      expect(sentence, isNot(contains(l10n.humorCategoryMeme)));
    });

    test('an empty profile never throws', () {
      expect(
        () => HumorProfileDisplay.summarySentence(
          l10nTr(),
          UserHumorProfile.empty,
        ),
        returnsNormally,
      );
    });
  });

  group('result screen', () {
    testWidgets('shows named traits and no false precision', (tester) async {
      final source = MockHumorDataSource(
        profile: _profile({
          HumorCategory.sarcasm: 88,
          HumorCategory.absurd: 79,
          HumorCategory.dry: 71,
          HumorCategory.cringe: 22,
        }),
      );

      await tester.pumpWidget(
        HumorScope(
          repository: HumorRepositoryImpl(dataSource: source),
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('tr'),
            home: HumorCalibrationResultPage(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final l10n = l10nTr();
      expect(find.text(l10n.humorResultTitle), findsOneWidget);
      expect(find.text(l10n.humorCategorySarcasm), findsOneWidget);
      expect(find.text(l10n.humorResultEvolvesNote), findsOneWidget);

      // Strength words, not percentages.
      expect(find.text(l10n.humorResultStrengthHigh), findsWidgets);
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('88'), findsNothing);
      expect(find.textContaining('.'), findsWidgets); // sentences, not decimals

      // Internal vocabulary must not leak.
      for (final internal in ['vector', 'anchor', 'cosine', 'confidence']) {
        expect(find.textContaining(internal), findsNothing);
      }
    });

    testWidgets('offers a way onward and a way to keep going', (tester) async {
      final source = MockHumorDataSource(
        profile: _profile({HumorCategory.meme: 82}),
      );
      var done = false;

      await tester.pumpWidget(
        HumorScope(
          repository: HumorRepositoryImpl(dataSource: source),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('tr'),
            home: HumorCalibrationResultPage(onDone: () => done = true),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final l10n = l10nTr();
      expect(find.text(l10n.humorResultKeepGoing), findsOneWidget);
      await tester.tap(find.text(l10n.humorResultDone));
      await tester.pump();
      expect(done, isTrue);
    });
  });
}
