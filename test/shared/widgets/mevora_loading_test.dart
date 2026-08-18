import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('loading view exposes a progress indicator', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(const MevoraLoading.page(message: 'Finding people')),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Finding people'), findsOneWidget);
  });
}
