import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/shared/art/mevora_mark.dart';
import 'package:mevora/shared/art/mevora_motion.dart';
import 'package:mevora/shared/art/mevora_spot.dart';

import '../../helpers/pump_app.dart';

Widget _reducedMotion(Widget child) => wrapWithApp(
  Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child,
    ),
  ),
);

void main() {
  testWidgets('every art subject renders a spot illustration', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        Wrap(
          children: [
            for (final art in MevoraArt.values) MevoraSpot(art: art, size: 48),
          ],
        ),
      ),
    );

    expect(find.byType(MevoraSpot), findsNWidgets(MevoraArt.values.length));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a static spot does not keep the frame clock busy', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithApp(const MevoraSpot(art: MevoraArt.emptyMatches)),
    );
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('an animated spot loops', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(const MevoraSpot(art: MevoraArt.searching, animate: true)),
    );
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('an animated spot stays still under reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      _reducedMotion(const MevoraSpot(art: MevoraArt.searching, animate: true)),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('orbit loader animates', (tester) async {
    await tester.pumpWidget(wrapWithApp(const MevoraOrbitLoader()));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('orbit loader stays still under reduced motion', (tester) async {
    await tester.pumpWidget(_reducedMotion(const MevoraOrbitLoader()));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('success mark and boost burst play once and settle', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithApp(
        const Row(children: [MevoraSuccessMark(), MevoraBoostBurst()]),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('the mark carries the Mevora name for screen readers', (
    tester,
  ) async {
    await tester.pumpWidget(wrapWithApp(const MevoraMark()));
    expect(find.bySemanticsLabel('Mevora'), findsOneWidget);
  });
}
