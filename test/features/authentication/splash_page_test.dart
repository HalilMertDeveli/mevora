import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/authentication/presentation/pages/splash_page.dart';
import 'package:mevora/shared/animations/mevora_rive_animation.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/components/mevora_logo.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('splash shows only the lower loading rive', (tester) async {
    await tester.pumpWidget(wrapWithApp(const SplashPage(), scaffold: false));

    expect(find.byType(MevoraLogo), findsOneWidget);
    expect(find.byType(MevoraRiveAnimation), findsOneWidget);
    final rive = tester.widget<MevoraRiveAnimation>(
      find.byType(MevoraRiveAnimation),
    );
    expect(rive.asset, MevoraRiveAssets.loading);
    expect(rive.asset, isNot(MevoraRiveAssets.splash));
  });
}
