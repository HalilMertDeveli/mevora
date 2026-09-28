import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/authentication/presentation/pages/splash_page.dart';
import 'package:mevora/shared/art/mevora_mark.dart';
import 'package:mevora/shared/art/mevora_motion.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('splash shows the settling mark, wordmark and one loader', (
    tester,
  ) async {
    await tester.pumpWidget(wrapWithApp(const SplashPage(), scaffold: false));

    expect(find.byType(MevoraMarkIntro), findsOneWidget);
    expect(find.text('mevora'), findsOneWidget);
    expect(find.byType(MevoraOrbitLoader), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1300));
  });
}
