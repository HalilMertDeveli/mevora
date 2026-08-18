import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_dialog.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('dialog shows title and closes on confirm', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        Builder(
          builder: (context) {
            return MevoraButton(
              label: 'Open dialog',
              onPressed: () {
                unawaited(
                  MevoraDialog.show(
                    context,
                    title: 'Leave Mevora?',
                    message: 'You can return at any time.',
                  ),
                );
              },
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Leave Mevora?'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Leave Mevora?'), findsNothing);
  });
}
