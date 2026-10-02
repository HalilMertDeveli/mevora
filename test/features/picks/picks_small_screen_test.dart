import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/picks/presentation/controllers/mevora_picks_controller.dart';
import 'package:mevora/features/picks/presentation/widgets/pick_card.dart';
import 'package:mevora/features/picks/presentation/widgets/pick_type_badge.dart';
import 'package:mevora/features/picks/presentation/widgets/picks_view.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

import 'picks_fixtures.dart';

/// Found on a real phone (Samsung M22, 720x1600 at 2.0, Turkish): the first
/// Pick's Pass and Like buttons started under the tab bar, so nobody could
/// decide on the first person of the day without scrolling first. On a
/// 1080x2400 emulator everything fit, which is why it went unnoticed.
///
/// These tests load the app's real fonts. The default test font is far wider
/// than Manrope, wraps every line and would measure a layout no phone shows.
/// The fonts are loaded once, outside any test body.
Future<void> _loadAppFonts() async {
  const families = {
    'Fraunces': ['Fraunces-SemiBold.ttf'],
    'Manrope': [
      'Manrope-Regular.ttf',
      'Manrope-Medium.ttf',
      'Manrope-SemiBold.ttf',
      'Manrope-Bold.ttf',
    ],
  };
  for (final family in families.entries) {
    final loader = FontLoader(family.key);
    for (final file in family.value) {
      final bytes = File('assets/fonts/$file').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

/// What is left of 800 dp for the list on that phone, between the app bar and
/// the tab bar.
const _shortPhone = Size(360, 633);

/// The same space on a 1080x2400 emulator at 2.625.
const _tallPhone = Size(411, 739);

final _tr = lookupAppLocalizations(const Locale('tr'));

Map<String, dynamic> _humorPick(String uid, String name, {int rank = 0}) {
  // The Pick the phone showed: a humor match with a reason line and chips.
  return pickPayload(
    uid: uid,
    name: name,
    age: 29,
    pickType: 'humorMatch',
    labels: const ['humorMatch', 'bestOverall'],
    humorScore: 99,
    reasons: [
      {
        'type': 'humor',
        'score': 99,
        'strength': 'strong',
        'meta': <String, Object>{},
      },
      {
        'type': 'relationship',
        'score': null,
        'strength': 'strong',
        'meta': <String, Object>{},
      },
    ],
    rank: rank,
    overall: 81,
    distanceKm: 5,
  );
}

void main() {
  setUpAll(_loadAppFonts);

  late MevoraPicksController controller;

  Future<void> pumpPicks(
    WidgetTester tester, {
    required Size size,
    double textScale = 1.0,
    List<Map<String, dynamic>>? picks,
    Map<String, Object?>? learning,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    controller = MevoraPicksController(
      repository: FakeMevoraPicksRepository(
        batchOf(
          picks ??
              [
                _humorPick('selin', 'Selin'),
                pickPayload(uid: 'deniz', name: 'Deniz', rank: 1, overall: 76),
              ],
          learning: learning,
        ),
      ),
      removalDuration: Duration.zero,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('tr'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: PicksView(
            controller: controller,
            onOpenProfile: (_) {},
            onOpenLearning: (_) {},
          ),
        ),
      ),
    );
    await controller.load();
    await tester.pumpAndSettle();
  }

  Rect decisionBar(WidgetTester tester) =>
      tester.getRect(find.byType(PickDecisionBar).first);

  Size firstCard(WidgetTester tester) =>
      tester.getSize(find.byType(PickCard).first);

  Finder inFirstCard(Finder matching) =>
      find.descendant(of: find.byType(PickCard).first, matching: matching);

  double firstPortrait(WidgetTester tester) =>
      tester.getSize(inFirstCard(find.byType(InkWell)).first).height;

  double natural(WidgetTester tester) =>
      firstCard(tester).width / PickCard.photoAspectRatio;

  double floor(WidgetTester tester) =>
      firstCard(tester).width / PickCard.flattestPhotoAspectRatio;

  testWidgets('the first Pick can be decided without scrolling on a short '
      'phone', (tester) async {
    await pumpPicks(tester, size: _shortPhone);

    final bar = decisionBar(tester);
    expect(bar.top, greaterThan(0));
    expect(bar.bottom, lessThanOrEqualTo(_shortPhone.height));
    expect(tester.takeException(), isNull);
  });

  testWidgets('it is the portrait that gives way, and it stays a portrait', (
    tester,
  ) async {
    await pumpPicks(tester, size: _shortPhone);

    expect(firstPortrait(tester), lessThan(natural(tester)));
    expect(firstPortrait(tester), greaterThanOrEqualTo(floor(tester) - 0.5));
    // The name over the photo and the reason under it are both still there.
    expect(find.text('Selin, 29'), findsOneWidget);
    expect(find.textContaining('%99'), findsOneWidget);
  });

  testWidgets('a taller phone keeps the portrait at its full shape', (
    tester,
  ) async {
    await pumpPicks(tester, size: _tallPhone);

    expect(firstPortrait(tester), closeTo(natural(tester), 0.5));
    expect(decisionBar(tester).bottom, lessThanOrEqualTo(_tallPhone.height));
  });

  testWidgets('the next card does not change size when the first is decided', (
    tester,
  ) async {
    // Each card has the same room, whichever position it is in: a card that
    // moved up must not shrink under the member's finger.
    await pumpPicks(
      tester,
      size: _shortPhone,
      picks: [_humorPick('selin', 'Selin'), _humorPick('ada', 'Ada', rank: 1)],
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -420));
    await tester.pumpAndSettle();
    final ada = find.ancestor(
      of: find.text('Ada, 29'),
      matching: find.byType(PickCard),
    );
    final before = tester.getSize(ada);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 420));
    await tester.pumpAndSettle();
    await tester.tap(
      inFirstCard(find.widgetWithText(MevoraButton, _tr.picksPass)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Selin, 29'), findsNothing);
    expect(tester.getSize(ada), before);
    expect(decisionBar(tester).bottom, lessThanOrEqualTo(_shortPhone.height));
  });

  testWidgets('the portrait is never squeezed flatter than its floor', (
    tester,
  ) async {
    // The largest text that still gets a budget, on the short phone: the
    // reason takes more room, and the portrait stops giving way at its floor
    // rather than crowding the badge and the name together.
    await pumpPicks(tester, size: _shortPhone, textScale: 1.3);

    expect(firstPortrait(tester), greaterThanOrEqualTo(floor(tester) - 0.5));
    final badge = tester.getRect(inFirstCard(find.byType(PickTypeBadge)).first);
    final name = tester.getRect(find.text('Selin, 29'));
    expect(badge.bottom, lessThanOrEqualTo(name.top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('enlarged text keeps the card at its natural shape', (
    tester,
  ) async {
    await pumpPicks(tester, size: _shortPhone, textScale: 1.5);

    expect(firstPortrait(tester), closeTo(natural(tester), 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a very short screen scrolls instead of crushing the portrait', (
    tester,
  ) async {
    await pumpPicks(tester, size: const Size(320, 420));

    expect(firstPortrait(tester), greaterThanOrEqualTo(floor(tester) - 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('under the questions card a Pick takes a screen of its own', (
    tester,
  ) async {
    await pumpPicks(
      tester,
      size: _shortPhone,
      learning: {
        'required': false,
        'firstSetCompleted': true,
        'today': {'total': 10, 'answered': 0},
      },
    );

    // The header and the questions card fill the first screen; the card is
    // then sized for the screen it scrolls into, not for what is left of this
    // one.
    expect(firstCard(tester).height, lessThanOrEqualTo(_shortPhone.height));
    expect(firstPortrait(tester), greaterThan(floor(tester)));
    expect(tester.takeException(), isNull);
  });
}
