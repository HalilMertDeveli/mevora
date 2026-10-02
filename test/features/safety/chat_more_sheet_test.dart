import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/core/di/social_services_factory.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/chat/presentation/controllers/chat_controller.dart';
import 'package:mevora/features/matching/data/memory/in_memory_social_graph.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/safety/presentation/widgets/chat_more_sheet.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// The chat's "More" menu. Found on a real phone: a conversation whose match
/// had already ended still offered "Unmatch".
void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  Future<void> openMenu(WidgetTester tester, {required Match? match}) async {
    final services = createGraphSocialServices(
      graph: InMemorySocialGraph(now: () => DateTime(2026, 1, 1, 12)),
      uidSource: MutableAuthUidSource('aya'),
    );
    final controller = ChatController(
      matchId: 'aya_can',
      chatRepository: services.chatRepository,
      matchRepository: services.matchRepository,
      safetyRepository: services.safetyRepository,
      presenceRepository: services.presenceRepository,
      uidSource: services.uidSource,
    )..match = match;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      SocialScope(
        services: services,
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showChatMoreSheet(context, controller: controller),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Match match({required bool isActive}) {
    return Match(
      id: 'aya_can',
      userIds: const ['aya', 'can'],
      createdAt: DateTime(2026, 1, 1),
      isActive: isActive,
      unmatchedBy: isActive ? null : 'can',
    );
  }

  testWidgets('an active match can be unmatched, blocked or reported', (
    tester,
  ) async {
    await openMenu(tester, match: match(isActive: true));

    expect(find.text(en.unmatch), findsOneWidget);
    expect(find.text(en.block), findsOneWidget);
    expect(find.text(en.report), findsOneWidget);
  });

  testWidgets('an ended match no longer offers Unmatch', (tester) async {
    await openMenu(tester, match: match(isActive: false));

    expect(find.text(en.unmatch), findsNothing);
    // The person can still be blocked and reported from the old conversation.
    expect(find.text(en.block), findsOneWidget);
    expect(find.text(en.report), findsOneWidget);
  });

  testWidgets('a match that never loaded offers no Unmatch either', (
    tester,
  ) async {
    await openMenu(tester, match: null);

    expect(find.text(en.unmatch), findsNothing);
    expect(find.text(en.block), findsOneWidget);
    expect(find.text(en.report), findsOneWidget);
  });
}
