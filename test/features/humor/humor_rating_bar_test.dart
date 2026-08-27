import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_rating_bar.dart';
import 'package:mevora/l10n/app_localizations.dart';

final _en = lookupAppLocalizations(const Locale('en'));

Widget wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('rating bar shows five localized levels and reports taps', (
    tester,
  ) async {
    HumorRating? selected;
    await tester.pumpWidget(
      wrap(
        HumorRatingBar(
          onRated: (rating) => selected = rating,
        ),
      ),
    );

    expect(find.text(_en.humorHowFunny), findsOneWidget);
    expect(find.text(_en.humorRatingVeryFunny), findsOneWidget);
    expect(find.text(_en.humorRatingFunny), findsOneWidget);
    expect(find.text(_en.humorRatingNeutral), findsOneWidget);
    expect(find.text(_en.humorRatingNotFunny), findsOneWidget);
    expect(find.text(_en.humorRatingNotAtAll), findsOneWidget);

    await tester.tap(find.text(_en.humorRatingFunny));
    await tester.pump();

    expect(selected, HumorRating.funny);
  });
}
