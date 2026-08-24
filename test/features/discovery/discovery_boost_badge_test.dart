import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_display_status.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_boost_badge.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_profile_card.dart';
import 'package:mevora/l10n/app_localizations.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  testWidgets('boost badge is hidden when profile is not boosted', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const Scaffold(
          body: DiscoveryBoostBadge(),
        ),
      ),
    );
    expect(find.text(l10n.boostDiscoverBadge), findsOneWidget);
  });

  testWidgets('discovery card shows boost badge only when boosted', (tester) async {
    const boosted = DiscoveryCandidate(
      uid: 'boosted',
      displayName: 'Ada',
      age: 27,
      compatibilityScore: 72,
      compatibilityStatus: CompatibilityDisplayStatus.ready,
      isBoosted: true,
    );
    const normal = DiscoveryCandidate(
      uid: 'normal',
      displayName: 'Burak',
      age: 28,
      compatibilityScore: 72,
      compatibilityStatus: CompatibilityDisplayStatus.ready,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const Scaffold(
          body: SizedBox(
            height: 520,
            child: Column(
              children: [
                Expanded(child: DiscoveryProfileCard(candidate: boosted)),
                Expanded(child: DiscoveryProfileCard(candidate: normal)),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text(l10n.boostDiscoverBadge), findsOneWidget);
    expect(find.text('Ada, 27'), findsOneWidget);
    expect(find.text('Burak, 28'), findsOneWidget);
  });
}
