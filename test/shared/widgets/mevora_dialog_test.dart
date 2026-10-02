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

  testWidgets('dialog shows a preview above its message', (tester) async {
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
                    title: 'Send this photo?',
                    message: 'Your photo is sent end-to-end encrypted.',
                    confirmLabel: 'Send',
                    preview: const SizedBox(
                      key: Key('preview'),
                      width: 120,
                      height: 90,
                    ),
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

    final preview = find.byKey(const Key('preview'));
    expect(preview, findsOneWidget);
    expect(
      tester.getBottomLeft(preview).dy,
      lessThanOrEqualTo(
        tester.getTopLeft(find.text('Your photo is sent end-to-end encrypted.')).dy,
      ),
    );
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(preview, findsNothing);
  });
}
