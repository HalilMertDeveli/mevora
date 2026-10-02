import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/onboarding/presentation/onboarding_labels.dart';
import 'package:mevora/features/profile/domain/catalog/language_catalog.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_language_picker.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

void main() {
  const locales = [Locale('tr'), Locale('en')];

  // Text, one space, then a trailing icon made only of pictographs (a flag
  // is two regional indicators; the neutral icon is a single symbol).
  final labelWithIcon = RegExp(
    r'^(\S(?:.*\S)?) ([\u{1F1E6}-\u{1F1FF}]{2}|[\u{1F300}-\u{1FAFF}])$',
    unicode: true,
  );

  test('stored language ids are unchanged', () {
    expect(LanguageCatalog.values, const [
      'turkish',
      'english',
      'german',
      'french',
      'spanish',
      'italian',
      'russian',
      'arabic',
      'persian',
      'kurdish',
      'greek',
      'dutch',
      'portuguese',
      'chinese',
      'japanese',
      'korean',
    ]);
  });

  for (final locale in locales) {
    test('every language has a localized label with an icon ($locale)', () {
      final l10n = lookupAppLocalizations(locale);

      for (final id in LanguageCatalog.values) {
        final label = OnboardingLabels.language(l10n, id);
        final match = labelWithIcon.firstMatch(label);

        expect(match, isNotNull, reason: '$id -> "$label" has no icon suffix');
        expect(match!.group(1), isNot(id), reason: '$id is not localized');
      }
    });
  }

  test('a language keeps the same icon in every locale', () {
    String iconOf(Locale locale, String id) {
      final label = OnboardingLabels.language(
        lookupAppLocalizations(locale),
        id,
      );
      return labelWithIcon.firstMatch(label)!.group(2)!;
    }

    for (final id in LanguageCatalog.values) {
      expect(iconOf(locales.first, id), iconOf(locales.last, id), reason: id);
    }
  });

  group('ProfileLanguagePicker', () {
    Future<List<Set<String>>> pumpPicker(
      WidgetTester tester, {
      required Locale locale,
      required Set<String> selected,
    }) async {
      final changes = <Set<String>>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfileLanguagePicker(
                selected: selected,
                onChanged: changes.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return changes;
    }

    for (final locale in locales) {
      testWidgets('shows an icon on every chip ($locale)', (tester) async {
        await pumpPicker(tester, locale: locale, selected: const {});

        final chips = tester.widgetList<MevoraChip>(find.byType(MevoraChip));
        expect(chips, hasLength(LanguageCatalog.values.length));
        for (final chip in chips) {
          expect(
            labelWithIcon.hasMatch(chip.label),
            isTrue,
            reason: chip.label,
          );
        }
      });
    }

    testWidgets('selecting and deselecting reports stored ids', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('tr'));
      final changes = await pumpPicker(
        tester,
        locale: const Locale('tr'),
        selected: const {'turkish'},
      );

      await tester.tap(find.text(l10n.languageKurdish));
      await tester.tap(find.text(l10n.languageTurkish));

      expect(changes, [
        {'turkish', 'kurdish'},
        <String>{},
      ]);
    });

    testWidgets('refuses a ninth language', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('tr'));
      final eight = LanguageCatalog.values.take(8).toSet();
      final changes = await pumpPicker(
        tester,
        locale: const Locale('tr'),
        selected: eight,
      );

      await tester.tap(find.text(l10n.languageKorean));
      expect(changes, isEmpty);

      await tester.tap(find.text(l10n.languageTurkish));
      expect(changes.single, eight.difference({'turkish'}));
    });
  });
}
