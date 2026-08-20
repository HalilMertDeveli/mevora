import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/shared/animations/mevora_animations.dart';
import 'package:mevora/shared/widgets/mevora_avatar.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

import '../../helpers/pump_app.dart';

void main() {
  test('animation durations stay in the specified ranges', () {
    expect(AppDurations.button.inMilliseconds, inInclusiveRange(150, 200));
    expect(AppDurations.page.inMilliseconds, inInclusiveRange(200, 300));
    expect(
      AppDurations.discoveryCard.inMilliseconds,
      inInclusiveRange(200, 300),
    );
    expect(AppDurations.match.inMilliseconds, inInclusiveRange(600, 1000));
  });

  testWidgets('button press wrapper is present on MevoraButton', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(MevoraButton(label: 'Continue', onPressed: () {})),
    );

    expect(find.byType(MevoraPressScale), findsOneWidget);
  });

  testWidgets('photo fade keeps the incoming child', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        const MevoraPhotoFade(
          photoKey: 'one',
          child: Text('Photo one'),
        ),
      ),
    );

    expect(find.text('Photo one'), findsOneWidget);
  });

  testWidgets('match celebration reveals MATCH', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        const MevoraMatchCelebration(leftName: 'Ada', rightName: 'Mina'),
      ),
    );

    expect(find.byType(MevoraAvatar), findsNWidgets(2));
    await tester.pump(AppDurations.match);
    expect(find.text('IT\'S A MATCH'), findsOneWidget);
  });

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
