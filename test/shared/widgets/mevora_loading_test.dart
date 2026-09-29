import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/shared/art/mevora_motion.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('loading view exposes a progress indicator', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(const MevoraLoading.page(message: 'Finding people')),
    );

    expect(find.byType(MevoraOrbitLoader), findsOneWidget);
    expect(find.text('Finding people'), findsOneWidget);
  });
}
