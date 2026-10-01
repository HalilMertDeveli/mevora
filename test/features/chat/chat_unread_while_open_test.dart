import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/social_services_factory.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/chat/domain/repositories/chat_repository.dart';
import 'package:mevora/features/chat/presentation/controllers/chat_controller.dart';
import 'package:mevora/features/matching/data/memory/in_memory_social_graph.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';

import '../../helpers/fake_chat_repository.dart';

/// Stands in for the match document: the server trigger raises the
/// receiver's unread count per message, a participant may reset their own.
class _ServerMatches implements MatchRepository {
  _ServerMatches(this.match);

  Match match;
  final _changes = StreamController<Match?>.broadcast();
  final List<String> opened = [];
  bool refuseOpens = false;

  /// Holds back the acknowledgement of a reset that has already landed.
  Completer<void>? openGate;

  /// What sendMessageNotification does to the match for one message.
  void countMessageFor(String uid) {
    match = match.copyWith(
      unreadCounts: {...match.unreadCounts, uid: match.unreadFor(uid) + 1},
    );
    _changes.add(match);
  }

  // The optional limit keeps this override valid whether or not the
  // repository interface declares it.
  @override
  Stream<List<MatchListItem>> watchMatches(String uid, {int? limit}) =>
      const Stream.empty();

  @override
  Future<Match?> getMatch(String matchId) async => match;

  @override
  Stream<Match?> watchMatch(String matchId) async* {
    yield match;
    yield* _changes.stream;
  }

  @override
  Future<void> markOpened(String matchId, String uid) async {
    opened.add(uid);
    if (refuseOpens) {
      // A refused write rolls back: the listener sees the old count again.
      _changes.add(match);
      throw StateError('permission-denied');
    }
    match = match.copyWith(
      isNewFor: {...match.isNewFor, uid: false},
      unreadCounts: {...match.unreadCounts, uid: 0},
    );
    _changes.add(match);
    await openGate?.future;
  }

  void dispose() => unawaited(_changes.close());
}

void main() {
  const matchId = 'a_b';
  late _ServerMatches matches;

  /// Member a's device: every message it sends is incoming for b.
  late FakeChatRepository chat;

  Future<ChatController> openAsB({ChatRepository? chatRepository}) async {
    final auth = MutableAuthUidSource('b');
    final services = createGraphSocialServices(
      graph: InMemorySocialGraph(now: () => DateTime.utc(2026, 9, 30, 12)),
      uidSource: auth,
    );
    final controller = ChatController(
      matchId: matchId,
      chatRepository: chatRepository ?? chat,
      matchRepository: matches,
      safetyRepository: services.safetyRepository,
      presenceRepository: services.presenceRepository,
      uidSource: auth,
    );
    addTearDown(controller.dispose);
    await controller.start();
    await pumpEventQueue();
    return controller;
  }

  /// One message from a: the message document first, the trigger's count after.
  Future<void> aSends(String text) async {
    await chat.sendText(matchId: matchId, receiverId: 'b', text: text);
    await pumpEventQueue();
    matches.countMessageFor('b');
    await pumpEventQueue();
  }

  setUp(() {
    matches = _ServerMatches(
      Match(
        id: matchId,
        userIds: const ['a', 'b'],
        createdAt: DateTime.utc(2026, 9, 30),
        isActive: true,
        isNewFor: const {'a': false, 'b': false},
      ),
    );
    chat = FakeChatRepository(uid: 'a');
    addTearDown(matches.dispose);
    addTearDown(chat.dispose);
  });

  test('messages read in an open thread leave no unread count', () async {
    final controller = await openAsB();
    expect(matches.opened, ['b'], reason: 'the thread opens once');

    await aSends('one');
    await aSends('two');
    await aSends('three');

    expect(controller.messages.every((message) => message.isRead), isTrue);
    expect(matches.match.unreadFor('b'), 0);
    expect(controller.match?.unreadFor('b'), 0);
    // One reset per counted message on top of the open.
    expect(matches.opened.length, 4);
  });

  test('a count of 0 is not written again', () async {
    await openAsB();
    matches.opened.clear();

    // The message arrives and is read before the trigger has counted it.
    await chat.sendText(matchId: matchId, receiverId: 'b', text: 'one');
    await pumpEventQueue();
    expect(matches.opened, isEmpty);

    // A match change that leaves the viewer's count at 0.
    matches.countMessageFor('a');
    await pumpEventQueue();
    expect(matches.opened, isEmpty);
    expect(matches.match.unreadFor('a'), 1, reason: 'not the viewer\'s key');
  });

  test('a burst counted during one reset costs one more write', () async {
    await openAsB();
    await aSends('one');
    expect(matches.match.unreadFor('b'), 0);
    matches.opened.clear();

    final acknowledged = Completer<void>();
    matches.openGate = acknowledged;
    await aSends('two');
    expect(matches.opened.length, 1, reason: 'the reset is on its way');

    // Two more are counted before that write is acknowledged.
    await aSends('three');
    await aSends('four');
    expect(matches.opened.length, 1);
    expect(matches.match.unreadFor('b'), 2);

    matches.openGate = null;
    acknowledged.complete();
    await pumpEventQueue();
    expect(matches.opened.length, 2);
    expect(matches.match.unreadFor('b'), 0);
  });

  test('the count stays while a loaded message is still unread', () async {
    // A receipt that never lands leaves the message unread in the snapshot.
    final controller = await openAsB(chatRepository: _NoReceiptChat(chat));
    await chat.sendText(matchId: matchId, receiverId: 'b', text: 'one');
    await pumpEventQueue();
    matches.opened.clear();

    matches.countMessageFor('b');
    await pumpEventQueue();

    expect(controller.messages.single.isRead, isFalse);
    expect(matches.opened, isEmpty);
    expect(matches.match.unreadFor('b'), 1);
  });

  test('a refused reset is not retried until the count moves', () async {
    await openAsB();
    matches.opened.clear();
    matches.refuseOpens = true;

    await aSends('one');
    expect(matches.opened.length, 1);
    expect(matches.match.unreadFor('b'), 1);

    // Unrelated match changes replay the same count: no second attempt.
    matches.countMessageFor('a');
    await pumpEventQueue();
    expect(matches.opened.length, 1);

    matches.refuseOpens = false;
    await aSends('two');
    expect(matches.opened.length, 2);
    expect(matches.match.unreadFor('b'), 0);
  });

  test('a closed thread stops resetting the count', () async {
    final auth = MutableAuthUidSource('b');
    final services = createGraphSocialServices(
      graph: InMemorySocialGraph(now: () => DateTime.utc(2026, 9, 30, 12)),
      uidSource: auth,
    );
    final controller = ChatController(
      matchId: matchId,
      chatRepository: chat,
      matchRepository: matches,
      safetyRepository: services.safetyRepository,
      presenceRepository: services.presenceRepository,
      uidSource: auth,
    );
    await controller.start();
    await aSends('one');
    matches.opened.clear();

    controller.dispose();
    await aSends('two');

    expect(matches.opened, isEmpty);
    expect(matches.match.unreadFor('b'), 1);
  });
}

/// A chat repository whose read receipts never land.
class _NoReceiptChat extends FakeChatRepository {
  _NoReceiptChat(this._source) : super(uid: _source.uid);

  final FakeChatRepository _source;

  @override
  Stream<List<ChatMessage>> watchLatest(String matchId, {int limit = 30}) =>
      _source.watchLatest(matchId, limit: limit);

  @override
  Future<void> markRead(String matchId, List<ChatMessage> items) async {}
}
