import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/shared/animations/mevora_cover_shrink.dart';
import 'package:mevora/shared/animations/mevora_rive_animation.dart';

import '../../helpers/pump_app.dart';

class _TabHost extends StatefulWidget {
  const _TabHost();

  @override
  State<_TabHost> createState() => _TabHostState();
}

class _TabHostState extends State<_TabHost> {
  int index = 0;

  void go(int value) => setState(() => index = value);

  @override
  Widget build(BuildContext context) {
    return MevoraCoverShrinkGate(playToken: index, child: Text('tab-$index'));
  }
}

void main() {
  testWidgets('cover overlay stays compact — never fills the viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithApp(const MevoraCoverShrinkOverlay(progress: 0)),
    );

    final overlay = tester.getSize(
      find.byKey(MevoraCoverShrinkOverlay.overlayKey),
    );
    final body = tester.getSize(find.byType(Scaffold));
    expect(overlay.width, lessThan(body.width * 0.35));
    expect(overlay.height, lessThan(body.height * 0.25));
    expect(find.byType(MevoraRiveAnimation), findsOneWidget);
  });

  testWidgets('cover overlay is gone when progress completes', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(const MevoraCoverShrinkOverlay(progress: 1)),
    );

    expect(find.byKey(MevoraCoverShrinkOverlay.overlayKey), findsNothing);
    expect(find.byType(MevoraRiveAnimation), findsNothing);
  });

  testWidgets('tab token change plays then dismisses the overlay', (
    tester,
  ) async {
    await tester.pumpWidget(wrapWithApp(const _TabHost()));
    expect(find.byKey(MevoraCoverShrinkOverlay.overlayKey), findsNothing);
    expect(find.text('tab-0'), findsOneWidget);

    tester.state<_TabHostState>(find.byType(_TabHost)).go(1);
    await tester.pump();
    expect(find.byKey(MevoraCoverShrinkOverlay.overlayKey), findsOneWidget);
    expect(find.text('tab-1'), findsOneWidget);

    await tester.pump(AppDurations.coverShrink);
    expect(find.byKey(MevoraCoverShrinkOverlay.overlayKey), findsNothing);
    expect(find.text('tab-1'), findsOneWidget);
  });

  testWidgets('reduced motion skips the tab cover', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: _TabHost(),
        ),
      ),
    );

    tester.state<_TabHostState>(find.byType(_TabHost)).go(2);
    await tester.pump();
    expect(find.byKey(MevoraCoverShrinkOverlay.overlayKey), findsNothing);
    expect(find.text('tab-2'), findsOneWidget);
  });

  testWidgets('gate disposes while the cover is playing', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        const MevoraCoverShrinkGate(
          playToken: 0,
          playOnFirstBuild: true,
          child: Text('live'),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(MevoraCoverShrinkOverlay.overlayKey), findsOneWidget);

    await tester.pumpWidget(wrapWithApp(const SizedBox.shrink()));
    await tester.pump();
  });
}
