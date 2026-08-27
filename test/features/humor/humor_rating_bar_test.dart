import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_rating_bar.dart';
import 'package:mevora/l10n/app_localizations.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _tr = lookupAppLocalizations(const Locale('tr'));

Widget wrap(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    theme: AppTheme.light(),
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('rating bar shows only binary Funny / Not funny', (tester) async {
    HumorRating? selected;
    await tester.pumpWidget(
      wrap(
        HumorRatingBar(
          onRated: (rating) => selected = rating,
        ),
      ),
    );

    expect(find.text(_en.humorHowFunny), findsOneWidget);
    expect(find.text(_en.humorRatingFunny), findsOneWidget);
    expect(find.text(_en.humorRatingNotFunny), findsOneWidget);
    expect(find.text(_en.humorRatingVeryFunny), findsNothing);
    expect(find.text(_en.humorRatingNeutral), findsNothing);
    expect(find.text(_en.humorRatingNotAtAll), findsNothing);

    await tester.tap(find.text(_en.humorRatingFunny));
    await tester.pump();
    expect(selected, HumorRating.funny);

    await tester.tap(find.text(_en.humorRatingNotFunny));
    await tester.pump();
    expect(selected, HumorRating.notFunny);
  });

  testWidgets('binary rating bar localizes in Turkish', (tester) async {
    await tester.pumpWidget(
      wrap(
        HumorRatingBar(onRated: (_) {}),
        locale: const Locale('tr'),
      ),
    );
    expect(find.text(_tr.humorHowFunny), findsOneWidget);
    expect(find.text(_tr.humorRatingFunny), findsOneWidget);
    expect(find.text(_tr.humorRatingNotFunny), findsOneWidget);
  });

  testWidgets('rating bar lays out on narrow phones', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    await tester.pumpWidget(
      wrap(
        const Align(
          alignment: Alignment.bottomCenter,
          child: HumorRatingBar(onRated: _noop),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });
}

void _noop(HumorRating _) {}
