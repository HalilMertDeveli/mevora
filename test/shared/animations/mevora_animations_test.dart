import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
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
    expect(find.text('You chose each other'), findsOneWidget);
    expect(find.text('NEW MATCH'), findsOneWidget);
    expect(find.text('Back to your picks'), findsOneWidget);
  });

  testWidgets('a new match can be answered without scrolling on a short '
      'phone', (tester) async {
    // 720x1600 at 2.0, less the app bar and the tab bar. With the "why you
    // match" panel above them, "Say hello" started below the fold.
    const screen = Size(360, 633);
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrapWithApp(
        MevoraMatchCelebration(
          leftName: 'Ada',
          rightName: 'Mina',
          compatibilitySection: const SizedBox(
            key: Key('why-you-match'),
            height: 420,
          ),
          onSendMessage: () {},
          onKeepExploring: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(AppDurations.match);

    for (final label in ['Say hello', 'Back to your picks']) {
      final rect = tester.getRect(find.text(label));
      expect(rect.top, greaterThanOrEqualTo(0), reason: label);
      expect(rect.bottom, lessThanOrEqualTo(screen.height), reason: label);
    }
    // The panel is still there, in the part that scrolls.
    expect(find.byKey(const Key('why-you-match')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('when everything fits, the actions still follow the copy', (
    tester,
  ) async {
    // Pinned only when they would otherwise be off screen: on a tall phone
    // with a short panel they must not drop to the bottom edge.
    const screen = Size(411, 914);
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrapWithApp(
        MevoraMatchCelebration(
          leftName: 'Ada',
          rightName: 'Mina',
          compatibilitySection: const SizedBox(
            key: Key('why-you-match'),
            height: 120,
          ),
          onSendMessage: () {},
          onKeepExploring: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(AppDurations.match);

    final panelBottom = tester
        .getRect(find.byKey(const Key('why-you-match')))
        .bottom;
    final button = tester.getRect(
      find.widgetWithText(MevoraButton, 'Say hello'),
    );
    expect(button.top - panelBottom, closeTo(AppSpacing.xl, 0.5));
    expect(button.bottom, lessThan(screen.height - 100));
  });

  testWidgets('a phone on its side scrolls the whole celebration', (
    tester,
  ) async {
    // No room to pin three buttons: nothing may overflow, and the actions
    // are reached by scrolling, as before.
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrapWithApp(
        MevoraMatchCelebration(
          leftName: 'Ada',
          rightName: 'Mina',
          compatibilitySection: const SizedBox(height: 300),
          onSendMessage: () {},
          onViewAnswers: () {},
          onKeepExploring: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(AppDurations.match);

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Back to your picks'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Say hello'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
