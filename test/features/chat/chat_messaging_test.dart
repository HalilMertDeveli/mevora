import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/social_services_factory.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/features/chat/domain/chat_policy.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/chat/domain/repositories/chat_repository.dart';
import 'package:mevora/features/chat/domain/usecases/chat_usecases.dart';
import 'package:mevora/features/chat/presentation/controllers/chat_controller.dart';
import 'package:mevora/features/matching/data/memory/in_memory_social_graph.dart';
import 'package:mevora/features/matching/domain/models/match.dart';

import '../../helpers/fake_chat_repository.dart';

void main() {
  final match = Match(
    id: 'a_b',
    userIds: const ['a', 'b'],
    createdAt: DateTime.utc(2026, 8, 18),
    isActive: true,
  );

  test('match-only send rejects unmatched and empty text', () async {
    final chat = FakeChatRepository(uid: 'a');
    addTearDown(chat.dispose);
    final send = SendChatText(chat);

    final unmatched = await send.call(
      match: match.copyWith(isActive: false),
      senderId: 'a',
      receiverId: 'b',
      text: 'hi',
      blocked: false,
    );
    expect(unmatched.isError, isTrue);
    expect(unmatched.failureOrNull, isA<AuthzFailure>());

    final empty = await send.call(
      match: match,
      senderId: 'a',
      receiverId: 'b',
      text: '  ',
      blocked: false,
    );
    expect(empty.isError, isTrue);

    final ok = await send.call(
      match: match,
      senderId: 'a',
      receiverId: 'b',
      text: 'hi',
      blocked: false,
    );
    expect(ok.isSuccess, isTrue);
  });

  test('pagination does not return the full history', () async {
    final chat = FakeChatRepository(uid: 'a');
    addTearDown(chat.dispose);
    ChatMessage? last;
    for (var i = 0; i < 40; i++) {
      last = await chat.sendText(
        matchId: 'a_b',
        receiverId: 'b',
        text: 'm$i',
      );
    }
    final older = await chat.loadOlder(
      matchId: 'a_b',
      before: last!,
      limit: 10,
    );
    expect(older.messages.length, 10);
    expect(older.hasMore, isTrue);
    expect(older.messages.length, lessThan(40));
  });

  test('ChatController typing is debounced and cleared on idle', () async {
    final graph = InMemorySocialGraph(now: () => DateTime.utc(2026, 8, 18, 12));
    graph.seedProfile('a', name: 'Ada');
    graph.seedProfile('b', name: 'Bea');
    graph.recordSwipe(actorUid: 'a', targetUserId: 'b', action: 'like');
    graph.recordSwipe(actorUid: 'b', targetUserId: 'a', action: 'like');
    final auth = MutableAuthUidSource('a');
    final services = createGraphSocialServices(graph: graph, uidSource: auth);
    final controller = ChatController(
      matchId: match.id,
      chatRepository: services.chatRepository,
      matchRepository: services.matchRepository,
      safetyRepository: services.safetyRepository,
      presenceRepository: services.presenceRepository,
      uidSource: auth,
    );
    addTearDown(controller.dispose);
    await controller.start();
    controller.onComposerChanged('h');
    expect(graph.typing[match.id], isNull);
    await Future<void>.delayed(ChatPolicy.typingDebounce + const Duration(milliseconds: 20));
    expect(graph.typing[match.id]?.containsKey('a'), isTrue);
  });

  test('sender can delete own message, not the other side', () async {
    final chat = FakeChatRepository(uid: 'a');
    addTearDown(chat.dispose);
    final sent = await chat.sendText(
      matchId: 'a_b',
      receiverId: 'b',
      text: 'secret',
    );
    final del = DeleteChatMessage(chat);
    final denied = await del.call(
      message: sent.copyWith(senderId: 'b'),
      uid: 'a',
      matchId: 'a_b',
    );
    expect(denied.isError, isTrue);

    final ok = await del.call(message: sent, uid: 'a', matchId: 'a_b');
    expect(ok.isSuccess, isTrue);
    expect(chat.messages['a_b']!.first.deleted, isTrue);

    final image = await SendChatImage(chat).call(
      match: match,
      senderId: 'a',
      receiverId: 'b',
      blocked: false,
      media: const ChatMediaBytes(bytes: [1, 2, 3], contentType: 'image/jpeg'),
    );
    expect(image.isSuccess, isTrue);
  });
}
