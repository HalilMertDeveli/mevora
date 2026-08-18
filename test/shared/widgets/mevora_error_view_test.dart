import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('error view can retry', (tester) async {
    var retried = false;

    await tester.pumpWidget(
      wrapWithApp(
        MevoraErrorView(
          title: 'Could not load',
          message: 'Check your connection.',
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.text('Could not load'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });
}
