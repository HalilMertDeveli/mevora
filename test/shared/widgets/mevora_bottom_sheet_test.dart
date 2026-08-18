import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/shared/widgets/mevora_bottom_sheet.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('bottom sheet shows title and content', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        Builder(
          builder: (context) {
            return MevoraButton(
              label: 'Open sheet',
              onPressed: () {
                unawaited(
                  MevoraBottomSheet.show<void>(
                    context,
                    title: 'Filters',
                    child: const Text('Age and distance'),
                  ),
                );
              },
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Filters'), findsOneWidget);
    expect(find.text('Age and distance'), findsOneWidget);
  });
}
