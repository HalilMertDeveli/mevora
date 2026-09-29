import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_display_status.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_discover_badge.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_signal.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_category_bar.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/pump_app.dart';

final _en = lookupAppLocalizations(const Locale('en'));

void main() {
  test('signals keep only scored dimensions, strongest first', () {
    final ranked = rankSignals({
      CompatibilitySignalKind.music: 60,
      CompatibilitySignalKind.relationship: 88,
      CompatibilitySignalKind.lifestyle: null,
      CompatibilitySignalKind.questions: 0,
    });

    expect(ranked.map((s) => s.kind), [
      CompatibilitySignalKind.relationship,
      CompatibilitySignalKind.music,
    ]);
  });

  test('Discover never surfaces the pre-match music compatibility score', () {
    const candidate = DiscoveryCandidate(
      uid: 'u1',
      displayName: 'Ada',
      age: 27,
      photos: [],
      musicCompatibilityScore: 91,
    );

    expect(
      discoverySignals(
        candidate,
      ).where((s) => s.kind == CompatibilitySignalKind.music),
      isEmpty,
    );
  });

  testWidgets('ring shows the score and exposes it to screen readers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      wrapWithApp(const CompatibilityRing(score: 84, animate: false)),
    );

    expect(find.text('84'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(CompatibilityRing)),
      matchesSemantics(label: _en.compatScoreHeading, value: '84%'),
    );
    handle.dispose();
  });

  testWidgets('the Discover strip leads with the reason, then the ring', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      wrapWithApp(
        DiscoveryCompatibilityScore(
          score: 76,
          reason: 'You both answered the future-plans questions alike',
          signals: const [
            (kind: CompatibilitySignalKind.relationship, score: 88),
            (kind: CompatibilitySignalKind.music, score: 70),
          ],
          onWhyTap: () => opened = true,
        ),
      ),
    );

    expect(
      find.text('You both answered the future-plans questions alike'),
      findsOneWidget,
    );
    expect(find.text(_en.compatCategoryMusic), findsOneWidget);
    expect(find.byType(CompatibilityRing), findsOneWidget);
    await tester.tap(find.byType(DiscoveryCompatibilityScore));
    expect(opened, isTrue);
  });

  testWidgets('a calculating score shows the loader, not a number', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithApp(
        const DiscoveryCompatibilityScore(
          score: 0,
          status: CompatibilityDisplayStatus.calculating,
        ),
      ),
    );

    expect(find.text(_en.compatCalculating), findsOneWidget);
    expect(find.byType(CompatibilityRing), findsNothing);
  });
}
