import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/shared/animations/mevora_animations.dart';
import 'package:mevora/shared/art/mevora_mark.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:mevora/shared/widgets/mevora_avatar.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

import '../../helpers/pump_app.dart';

void main() {
  test('animation durations stay in the specified ranges', () {
    expect(AppDurations.fast.inMilliseconds, inInclusiveRange(120, 180));
    expect(AppDurations.normal.inMilliseconds, inInclusiveRange(200, 300));
    expect(AppDurations.slow.inMilliseconds, inInclusiveRange(350, 450));
    expect(AppDurations.button.inMilliseconds, inInclusiveRange(150, 200));
    expect(AppDurations.page.inMilliseconds, inInclusiveRange(200, 300));
    expect(
      AppDurations.discoveryCard.inMilliseconds,
      inInclusiveRange(200, 300),
    );
    // The match moment is the one deliberately longer beat: portraits
    // converge, the seal lands, then the copy arrives.
    expect(AppDurations.match.inMilliseconds, inInclusiveRange(1000, 1600));
  });

  testWidgets('page transition renders the route body directly', (
    tester,
  ) async {
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

  testWidgets('match moment converges two portraits under the Mevora seal', (
    tester,
  ) async {
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
    expect(find.byType(MevoraMark), findsOneWidget);
    expect(find.text('You found a strong connection.'), findsOneWidget);
    expect(find.text('STRONG CONNECTION'), findsOneWidget);
    expect(find.text('Keep exploring'), findsOneWidget);
  });

  testWidgets('like burst plays once without looping', (tester) async {
    await tester.pumpWidget(wrapWithApp(const MevoraLikeBurst(play: true)));

    await tester.pump(AppDurations.like);
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  test('like burst uses the Mevora heart glyph', () {
    expect(MevoraIcons.liked.fontPackage, 'phosphor_flutter');
  });
}
