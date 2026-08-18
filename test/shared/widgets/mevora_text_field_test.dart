import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/shared/widgets/mevora_text_field.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('text field shows label and reports changes', (tester) async {
    var value = '';

    await tester.pumpWidget(
      wrapWithApp(
        MevoraTextField(
          label: 'Email',
          hint: 'you@mevora.app',
          onChanged: (next) => value = next,
        ),
      ),
    );

    expect(find.text('Email'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ada@mevora.app');
    expect(value, 'ada@mevora.app');
  });
}
