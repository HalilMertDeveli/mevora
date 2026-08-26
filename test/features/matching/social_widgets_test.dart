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

  testWidgets('chat bubbles show text time photo and voice', (tester) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: ListView(
            children: [
              ChatBubble(
                isMine: true,
                message: ChatMessage(
                  id: '1',
                  senderId: 'a',
                  receiverId: 'b',
                  text: 'Merhaba',
                  type: MessageType.text,
                  createdAt: DateTime(2026, 1, 1, 12, 5),
                  status: MessageStatus.read,
                ),
              ),
              ChatBubble(
                isMine: false,
                message: ChatMessage(
                  id: '2',
                  senderId: 'b',
                  receiverId: 'a',
                  text: '',
                  type: MessageType.voice,
                  createdAt: DateTime(2026, 1, 1, 12, 6),
                  status: MessageStatus.sent,
                  durationMs: 2500,
                  mediaUrl: 'https://example.invalid/voice.m4a',
                ),
              ),
              ChatBubble(
                isMine: true,
                message: ChatMessage(
                  id: '3',
                  senderId: 'a',
                  receiverId: 'b',
                  text: '',
                  type: MessageType.image,
                  createdAt: DateTime(2026, 1, 1, 12, 7),
                  status: MessageStatus.sent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Merhaba'), findsOneWidget);
    expect(find.text('12:05'), findsOneWidget);
    expect(find.byIcon(Icons.done_all), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });

  testWidgets('composer exposes attach and voice actions', (tester) async {
    final composer = TextEditingController();
    addTearDown(composer.dispose);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatComposer(
              controller: composer,
              enabled: true,
              onChanged: (_) {},
              onSend: () {},
              onAttachPhoto: () {},
              onAttachCamera: () {},
              onVoiceStart: () {},
              onVoiceEnd: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('chat-attach')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-record-voice')), findsOneWidget);
    expect(find.byTooltip(_l10n.attachPhoto), findsOneWidget);
    expect(find.byTooltip(_l10n.recordVoice), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-attach')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-attach-photo')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-attach-camera')), findsOneWidget);
    expect(find.text(_l10n.attachPhoto), findsWidgets);
    expect(find.text(_l10n.takePhoto), findsOneWidget);
  });

  testWidgets('composer swaps mic for send when text is entered', (tester) async {
    final composer = TextEditingController();
    addTearDown(composer.dispose);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatComposer(
              controller: composer,
              enabled: true,
              onChanged: (_) {},
              onSend: () {},
              onAttachPhoto: () {},
              onAttachCamera: () {},
              onVoiceStart: () {},
              onVoiceEnd: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('chat-record-voice')), findsOneWidget);
    expect(find.byIcon(Icons.send_rounded), findsNothing);

    composer.text = 'Merhaba';
    composer.notifyListeners();
    await tester.pump();

    expect(find.byKey(const ValueKey('chat-record-voice')), findsNothing);
    expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    expect(find.byTooltip(_l10n.send), findsOneWidget);
  });

  testWidgets('incoming call accept and reject', (tester) async {
    final graph = InMemorySocialGraph(now: () => DateTime(2026, 1, 1, 12));
    graph.seedProfile('aya', name: 'Ayşe');
    graph.seedProfile('can', name: 'Can');
    final auth = MutableAuthUidSource('aya');
    graph.recordSwipe(actorUid: 'aya', targetUserId: 'can', action: 'like');
    graph.recordSwipe(actorUid: 'can', targetUserId: 'aya', action: 'like');
    graph.createCall(
      actorUid: 'can',
      matchId: 'aya_can',
      receiverId: 'aya',
    );
    final services = createGraphSocialServices(graph: graph, uidSource: auth);
    await tester.pumpWidget(
      SocialScope(
        services: services,
        child: _app(IncomingCallPage(callId: graph.calls.keys.first)),
      ),
    );
    await tester.pump();
    expect(find.text(_l10n.incomingCall), findsOneWidget);
    expect(find.text(_l10n.decline), findsOneWidget);
    expect(find.text(_l10n.accept), findsOneWidget);
  });
}
