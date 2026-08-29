import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_snapshot.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_reveal_section.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/features/matching/presentation/widgets/match_connection_tile.dart';
import 'package:mevora/l10n/app_localizations.dart';

Widget _app(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(body: child),
  );
}

MatchListItem _item({CompatibilitySnapshot? compatibility}) {
  final match = Match(
    id: 'a_b',
    userIds: const ['a', 'b'],
    createdAt: DateTime(2026, 3, 1),
    isActive: true,
    lastMessage: 'Hey',
    compatibilitySnapshots: {
      if (compatibility != null) 'a': compatibility,
    },
  );
  return MatchListItem(
    match: match,
    otherUserId: 'b',
    name: 'Elif',
    compatibility: match.compatibilityFor('a'),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('old match / race: null breakdown shows no percent', (tester) async {
    await tester.pumpWidget(
      _app(
        MatchConnectionTile(
          item: _item(),
          currentUid: 'a',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('%'), findsNothing);
    expect(find.text('0%'), findsNothing);
  });

  testWidgets('new match with snapshot shows real score and Why You Match', (
    tester,
  ) async {
    final snap = CompatibilitySnapshot.fromMap({
      'compatibilityScore': 94,
      'compatibilityBreakdown': {
        'overallScore': 94,
        'relationshipScore': 96,
        'interestScore': 88,
        'lifestyleScore': 91,
        'musicScore': 80,
      },
      'sharedInterests': ['travel'],
      'compatibilityReasons': ['Shared interests'],
    })!;
    var whyTapped = false;
    await tester.pumpWidget(
      _app(
        MatchConnectionTile(
          item: _item(compatibility: snap),
          currentUid: 'a',
          breakdown: snap.breakdown,
          onWhyTap: () => whyTapped = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('94%'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.whyYouMatch), findsOneWidget);
    await tester.tap(find.text(l10n.whyYouMatch));
    await tester.pumpAndSettle();
    expect(whyTapped, isTrue);
  });

  testWidgets('CompatibilityRevealSection renders snapshot breakdown', (
    tester,
  ) async {
    const breakdown = CompatibilityBreakdown(
      overallScore: 87,
      relationshipScore: 90,
      interestScore: 80,
      lifestyleScore: 70,
      musicScore: 60,
      questionScore: 50,
    );
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          child: CompatibilityRevealSection(
            breakdown: breakdown,
            reasons: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('87'), findsWidgets);
  });
}
