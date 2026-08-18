import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/core/di/social_services_factory.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/calls/presentation/pages/call_pages.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/chat/presentation/widgets/chat_widgets.dart';
import 'package:mevora/features/matching/data/memory/in_memory_social_graph.dart';
import 'package:mevora/features/matching/presentation/pages/matches_page.dart';
import 'package:mevora/l10n/app_localizations.dart';

final _l10n = lookupAppLocalizations(const Locale('tr'));

Widget _app(Widget home) {
  return MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('tr'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: home,
  );
}

void main() {
  testWidgets('match list shows photo name last message and new badge', (
    tester,
  ) async {
    final graph = InMemorySocialGraph(now: () => DateTime(2026, 1, 1, 12));
    graph.seedProfile('aya', name: 'Ayşe');
    graph.seedProfile('can', name: 'Can');
    final auth = MutableAuthUidSource('aya');
    graph.recordSwipe(actorUid: 'aya', targetUserId: 'can', action: 'like');
    graph.recordSwipe(actorUid: 'can', targetUserId: 'aya', action: 'like');
    final services = createGraphSocialServices(graph: graph, uidSource: auth);
    await tester.pumpWidget(
      SocialScope(
        services: services,
        child: _app(
          Builder(
            builder: (context) {
              final social = SocialScope.of(context);
              return MatchesPage(controller: social.matchesController);
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Can'), findsOneWidget);
    expect(find.text(_l10n.newMatch), findsWidgets);
  });

  testWidgets('chat bubble and typing indicator render', (tester) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Column(
            children: [
              ChatBubble(
                isMine: true,
                message: ChatMessage(
                  id: '1',
                  senderId: 'a',
                  receiverId: 'b',
                  text: 'Merhaba',
                  type: MessageType.text,
                  createdAt: DateTime(2026),
                  status: MessageStatus.sent,
                ),
              ),
              const TypingDots(name: 'Ayşe'),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Merhaba'), findsOneWidget);
    expect(find.text('Ayşe ${_l10n.typing}'), findsOneWidget);
  });

  testWidgets('incoming call shows name and actions', (tester) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: IncomingCallPulse(
            child: Column(
              children: [
                const Text('Ayşe'),
                Text(_l10n.incomingCall),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text(_l10n.incomingCall), findsOneWidget);
    expect(find.text('Ayşe'), findsOneWidget);
  });

  testWidgets('video controls and turkish error render', (tester) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Column(
            children: [
              Text(_l10n.callFailed),
              CallControls(
                cameraOn: false,
                micOn: false,
                speakerOn: true,
                onToggleCamera: () {},
                onToggleMute: () {},
                onToggleSpeaker: () {},
                onSwitchCamera: () {},
                onEnd: () {},
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text(_l10n.callFailed), findsOneWidget);
    expect(find.byTooltip(_l10n.endCall), findsOneWidget);
  });
}
