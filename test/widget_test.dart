import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/app.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/constants/app_constants.dart';
import 'package:mevora/core/services/app_logger.dart';

void main() {
  testWidgets('app boots into the design system preview', (tester) async {
    const environment = AppEnvironment.development;
    await tester.pumpWidget(
      const MevoraApp(
        config: AppConfig(environment: environment),
        logger: AppLogger(environment: environment),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(AppConstants.appName.toUpperCase()), findsOneWidget);
    expect(find.text(AppConstants.tagline), findsOneWidget);
    expect(find.text('Mevora Dev'), findsOneWidget);
  });
}
