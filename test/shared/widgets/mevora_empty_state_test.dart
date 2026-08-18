import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('empty state shows action', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      wrapWithApp(
        MevoraEmptyState(
          icon: Icons.people_outline,
          title: 'No profiles',
          message: 'Try expanding your filters.',
          actionLabel: 'Adjust filters',
          onAction: () => tapped = true,
        ),
      ),
    );

    expect(find.text('No profiles'), findsOneWidget);
    await tester.tap(find.text('Adjust filters'));
    expect(tapped, isTrue);
  });
}
