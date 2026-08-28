import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/humor/data/services/sponsored_break_humor_ad_service.dart';
import 'package:mevora/features/humor/domain/config/humor_ads_settings.dart';
import 'package:mevora/features/humor/domain/services/humor_ad_service.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Sponsored break ad UI fits target phone sizes without overflow.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const targetSizes = <Size>[
    Size(360, 640),
    Size(360, 800),
    Size(390, 844),
    Size(412, 915),
    Size(430, 932),
  ];

  testWidgets('sponsored break fits target sizes', (tester) async {
    for (final size in targetSizes) {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = SponsoredBreakHumorAdService(
        settings: const HumorAdsSettings(minWatchSeconds: 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () {
                      unawaited(
                        service.show(
                          const HumorAdRequest(placementId: 'test'),
                          hostContext: context,
                        ),
                      );
                    },
                    child: const Text('Show ad'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Show ad'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      final continueButton = find.descendant(
        of: find.byType(Scaffold).last,
        matching: find.byType(FilledButton),
      );
      expect(continueButton, findsOneWidget);
      final button = tester.widget<FilledButton>(continueButton);
      expect(button.onPressed, isNotNull);

      await tester.tap(continueButton);
      await tester.pumpAndSettle();
    }
  });
}
