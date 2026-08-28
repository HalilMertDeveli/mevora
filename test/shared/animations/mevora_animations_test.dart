import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/shared/animations/mevora_animations.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:mevora/shared/widgets/mevora_avatar.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

import '../../helpers/pump_app.dart';

void main() {
  test('animation durations stay in the specified ranges', () {
    expect(AppDurations.button.inMilliseconds, inInclusiveRange(150, 200));
    expect(AppDurations.page.inMilliseconds, inInclusiveRange(200, 300));
    expect(AppDurations.coverShrink.inMilliseconds, inInclusiveRange(250, 400));
    expect(
      AppDurations.discoveryCard.inMilliseconds,
      inInclusiveRange(200, 300),
    );
    expect(AppDurations.match.inMilliseconds, inInclusiveRange(600, 1000));
  });

  testWidgets('page transition never mounts a cover overlay', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        Builder(
          builder: (context) {
            return MevoraPageTransitions.build(
              context,
              const AlwaysStoppedAnimation<double>(0.5),
              const AlwaysStoppedAnimation<double>(0),
              const Text('route-body'),
            );
          },
        ),
      ),
    );

    expect(find.text('route-body'), findsOneWidget);
    expect(find.byType(MevoraCoverShrinkOverlay), findsNothing);
    expect(find.byType(MevoraRiveAnimation), findsNothing);
  });

  testWidgets('button press wrapper is present on MevoraButton', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithApp(MevoraButton(label: 'Continue', onPressed: () {})),
    );

    expect(find.byType(MevoraPressScale), findsOneWidget);
  });

  testWidgets('photo fade keeps the incoming child', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        const MevoraPhotoFade(photoKey: 'one', child: Text('Photo one')),
      ),
    );

    expect(find.text('Photo one'), findsOneWidget);
  });

  testWidgets(
    'match celebration reveals MATCH without NetworkImage mock URLs',
    (tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          MevoraMatchCelebration(
            leftName: 'Ada',
            rightName: 'Mina',
            // Unknown mock:// URLs stay off NetworkImage.
            rightImage: MevoraNetworkImages.provider('mock://mina/0'),
            onKeepExploring: () {},
          ),
        ),
      );

      expect(find.byType(MevoraAvatar), findsNWidgets(2));
      await tester.pump();
      await tester.pump(AppDurations.match);
      expect(find.text('You found a strong connection.'), findsOneWidget);
      expect(find.text('Strong connection'), findsOneWidget);
      expect(find.text('Keep exploring'), findsOneWidget);
    },
  );

  testWidgets('like burst and pass motion render without looping', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithApp(
        const Stack(
          children: [
            MevoraPassMotion(active: true, child: Text('Passed')),
            MevoraLikeBurst(play: true),
          ],
        ),
      ),
    );

    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.text('Passed'), findsOneWidget);
    await tester.pump(AppDurations.like);
    await tester.pump(AppDurations.pass);
  });
}
