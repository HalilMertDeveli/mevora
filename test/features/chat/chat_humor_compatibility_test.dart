import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/config/feature_flags.dart';
import 'package:mevora/core/di/humor_scope.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/core/di/social_services_factory.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/chat/data/services/chat_audio_player.dart';
import 'package:mevora/features/chat/domain/services/chat_voice_recorder.dart';
import 'package:mevora/features/chat/presentation/pages/chat_page.dart';
import 'package:mevora/features/chat/presentation/widgets/chat_widgets.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_compatibility.dart';
import 'package:mevora/features/humor/domain/repositories/humor_repository.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_chat_starter_chip.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_compatibility_badge.dart';
import 'package:mevora/features/matching/data/memory/in_memory_social_graph.dart';
import 'package:mevora/l10n/app_localizations.dart';

final _tr = lookupAppLocalizations(const Locale('tr'));

const _matchId = 'aya_can';

class _IdleRecorder implements ChatVoiceRecorder {
  @override
  bool get isRecording => false;

  @override
  Future<void> start() async {}

  @override
  Future<RecordedVoice?> stop() async => null;

  @override
  Future<void> cancel() async {}
}

class _FakeHumorRepository implements HumorRepository {
  _FakeHumorRepository(this.compatibility);

  final HumorCompatibility compatibility;
  final requested = <String>[];

  @override
  Future<Result<HumorCompatibility>> getMatchCompatibility(
    String matchId,
  ) async {
    requested.add(matchId);
    return Success(compatibility);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Harness {
  _Harness() {
    graph.seedProfile('aya', name: 'Ayşe');
    graph.seedProfile('can', name: 'Can');
    graph.recordSwipe(actorUid: 'aya', targetUserId: 'can', action: 'like');
    graph.recordSwipe(actorUid: 'can', targetUserId: 'aya', action: 'like');
  }

  final graph = InMemorySocialGraph(now: () => DateTime(2026, 1, 1, 12));
  final auth = MutableAuthUidSource('aya');

  Widget app({required HumorRepository humor, bool humorLabEnabled = true}) {
    const environment = AppEnvironment.development;
    return AppScope(
      config: AppConfig(
        environment: environment,
        featureFlags: FeatureFlags(humorLabEnabled: humorLabEnabled),
      ),
      logger: const AppLogger(environment: environment),
      child: HumorScope(
        repository: humor,
        child: SocialScope(
          services: createGraphSocialServices(graph: graph, uidSource: auth),
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('tr'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: ChatPage(
              matchId: _matchId,
              voiceRecorder: _IdleRecorder(),
              audioPlayer: FakeChatAudioPlayer(),
            ),
          ),
        ),
      ),
    );
  }
}

const _shared = HumorCompatibility(
  available: true,
  score: 78,
  strongestShared: [HumorCategory.wordplay, HumorCategory.dry],
);

String _composerText(WidgetTester tester) {
  final field = tester.widget<TextField>(
    find.descendant(
      of: find.byType(ChatComposer),
      matching: find.byType(TextField),
    ),
  );
  return field.controller!.text;
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  testWidgets('empty chat: starter chip pre-fills the composer, never sends', (
    tester,
  ) async {
    final harness = _Harness();
    final humor = _FakeHumorRepository(_shared);

    await tester.pumpWidget(harness.app(humor: humor));
    await tester.pumpAndSettle();

    expect(humor.requested, [_matchId]);
    expect(find.text(_tr.chatEmptyTitle), findsOneWidget);
    expect(find.byType(HumorCompatibilityBadge), findsOneWidget);
    final starter = _tr.humorChatStarterWordplay;
    expect(find.text(starter), findsOneWidget);
    expect(_composerText(tester), isEmpty);

    await tester.tap(find.text(starter));
    await tester.pumpAndSettle();

    expect(_composerText(tester), starter);
    // Nothing went out: no bubble, no stored message, chat still empty.
    expect(find.byType(ChatBubble), findsNothing);
    expect(harness.graph.messages[_matchId] ?? const [], isEmpty);
    expect(find.text(_tr.chatEmptyTitle), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('chat with messages: badge stays, starter is not offered', (
    tester,
  ) async {
    final harness = _Harness();
    harness.graph.sendText(
      actorUid: 'can',
      matchId: _matchId,
      receiverId: 'aya',
      text: 'Selam!',
    );
    final humor = _FakeHumorRepository(_shared);

    await tester.pumpWidget(harness.app(humor: humor));
    await tester.pumpAndSettle();

    expect(find.text('Selam!'), findsOneWidget);
    expect(find.byType(HumorCompatibilityBadge), findsOneWidget);
    expect(find.byType(HumorChatStarterChip), findsNothing);

    await _unmount(tester);
  });

  testWidgets('humor lab off: chat renders without any humor call', (
    tester,
  ) async {
    final harness = _Harness();
    final humor = _FakeHumorRepository(_shared);

    await tester.pumpWidget(harness.app(humor: humor, humorLabEnabled: false));
    await tester.pumpAndSettle();

    expect(find.byType(ChatComposer), findsOneWidget);
    expect(find.text(_tr.chatEmptyTitle), findsOneWidget);
    expect(find.byType(HumorCompatibilityBadge), findsNothing);
    expect(find.byType(HumorChatStarterChip), findsNothing);
    expect(humor.requested, isEmpty);

    await _unmount(tester);
  });
}
