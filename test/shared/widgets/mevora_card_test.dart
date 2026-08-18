import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('card renders child and handles taps', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      wrapWithApp(
        MevoraCard(
          onTap: () => tapped = true,
          child: const Text('Profile card'),
        ),
      ),
    );

    expect(find.text('Profile card'), findsOneWidget);
    await tester.tap(find.text('Profile card'));
    expect(tapped, isTrue);
  });
}
