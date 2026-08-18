import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('primary button invokes onPressed', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      wrapWithApp(
        MevoraButton(
          label: 'Continue',
          onPressed: () => tapped = true,
        ),
      ),
    );

    await tester.tap(find.text('Continue'));
    expect(tapped, isTrue);
  });

  testWidgets('loading button does not invoke onPressed', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      wrapWithApp(
        MevoraButton(
          label: 'Continue',
          isLoading: true,
          onPressed: () => tapped = true,
        ),
      ),
    );

    await tester.tap(find.byType(MevoraButton));
    expect(tapped, isFalse);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
