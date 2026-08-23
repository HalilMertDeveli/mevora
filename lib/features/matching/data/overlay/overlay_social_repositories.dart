import 'dart:async';

import 'package:mevora/core/di/demo_social_hub.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/chat/domain/repositories/chat_repository.dart';
import 'package:mevora/features/matching/data/memory/graph_repositories.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';
import 'package:mevora/features/safety/domain/safety_policy.dart';

/// Merges Firebase matches with in-memory demo matches.
class OverlayMatchRepository implements MatchRepository {
  OverlayMatchRepository({
    required this.remote,
    required this.hub,
  });

  final MatchRepository remote;
  final DemoSocialHub hub;

  @override
  Stream<List<MatchListItem>> watchMatches(String uid) {
    final controller = StreamController<List<MatchListItem>>();
    var remoteItems = <MatchListItem>[];
    var localItems = <MatchListItem>[];

    void emit() {
      if (controller.isClosed) {
        return;
      }
      final seen = <String>{};
      final merged = <MatchListItem>[];
      for (final item in [...localItems, ...remoteItems]) {
        if (seen.add(item.match.id)) {
          merged.add(item);
        }
      }
      merged.sort((a, b) {
        final aTime = a.match.lastMessageAt ?? a.match.createdAt;
        final bTime = b.match.lastMessageAt ?? b.match.createdAt;
        return bTime.compareTo(aTime);
      });
      controller.add(merged);
    }

    final remoteSub = remote.watchMatches(uid).listen(
      (value) {
        remoteItems = value;
        emit();
      },
      onError: (_) => emit(),
    );
    final localSub = hub.matches.watchMatches(uid).listen(
      (value) {
        localItems = value;
        emit();
      },
      onError: controller.addError,
    );

    controller.onCancel = () async {
      await remoteSub.cancel();
      await localSub.cancel();
    };
    return controller.stream;
  }

  @override
  Future<Match?> getMatch(String matchId) async {
    final local = hub.graph.matches[matchId];
    if (local != null) {
      return local;
    }
    try {
      return await remote.getMatch(matchId);
    } on Object {
      return null;
    }
  }

  @override
  Stream<Match?> watchMatch(String matchId) async* {
    final local = hub.graph.matches[matchId];
    if (local != null) {
      yield local;
      return;
    }
    yield* remote.watchMatch(matchId);
  }

  @override
  Future<void> markOpened(String matchId, String uid) async {
    if (hub.graph.matches.containsKey(matchId)) {
      await hub.matches.markOpened(matchId, uid);
      return;
    }
    await remote.markOpened(matchId, uid);
  }
}

/// Routes demo conversations to the in-memory graph; real matches stay on Firebase.
class OverlayChatRepository implements ChatRepository {
  OverlayChatRepository({
    required this.remote,
    required this.hub,
  });

  final ChatRepository remote;
  final DemoSocialHub hub;

  bool _isDemo(String matchId) => hub.graph.matches.containsKey(matchId);

  @override
  Stream<List<ChatMessage>> watchLatest(String matchId, {int limit = 30}) {
    if (_isDemo(matchId)) {
      return hub.chat.watchLatest(matchId, limit: limit);
    }
    return remote.watchLatest(matchId, limit: limit);
  }

  @override
  Future<ChatPage> loadOlder({
    required String matchId,
    required ChatMessage before,
    int limit = 30,
  }) {
    if (_isDemo(matchId)) {
      return hub.chat.loadOlder(
        matchId: matchId,
        before: before,
        limit: limit,
      );
    }
    return remote.loadOlder(matchId: matchId, before: before, limit: limit);
  }

  @override
  Future<ChatMessage> sendText({
    required String matchId,
    required String receiverId,
    required String text,
  }) {
    if (_isDemo(matchId)) {
      return hub.chat.sendText(
        matchId: matchId,
        receiverId: receiverId,
        text: text,
      );
    }
    return remote.sendText(
      matchId: matchId,
      receiverId: receiverId,
      text: text,
    );
  }

  @override
  Future<ChatMessage> sendImage({
    required String matchId,
    required String receiverId,
    required ChatMediaBytes media,
    void Function(double progress)? onProgress,
  }) {
    final isDemo = _isDemo(matchId);
    if (isDemo) {
      return hub.chat.sendImage(
        matchId: matchId,
        receiverId: receiverId,
        media: media,
        onProgress: onProgress,
      );
    }
    return remote.sendImage(
      matchId: matchId,
      receiverId: receiverId,
      media: media,
      onProgress: onProgress,
    );
  }

  @override
  Future<ChatMessage> sendVoice({
    required String matchId,
    required String receiverId,
    required ChatMediaBytes media,
    void Function(double progress)? onProgress,
  }) {
    if (_isDemo(matchId)) {
      return hub.chat.sendVoice(
        matchId: matchId,
        receiverId: receiverId,
        media: media,
        onProgress: onProgress,
      );
    }
    return remote.sendVoice(
      matchId: matchId,
      receiverId: receiverId,
      media: media,
      onProgress: onProgress,
    );
  }

  @override
  Future<void> deleteMessage({
    required String matchId,
    required String messageId,
  }) {
    if (_isDemo(matchId)) {
      return hub.chat.deleteMessage(matchId: matchId, messageId: messageId);
    }
    return remote.deleteMessage(matchId: matchId, messageId: messageId);
  }

  @override
  Future<void> markDelivered(String matchId, List<ChatMessage> messages) {
    if (_isDemo(matchId)) {
      return hub.chat.markDelivered(matchId, messages);
    }
    return remote.markDelivered(matchId, messages);
  }

  @override
  Future<void> markRead(String matchId, List<ChatMessage> messages) {
    if (_isDemo(matchId)) {
      return hub.chat.markRead(matchId, messages);
    }
    return remote.markRead(matchId, messages);
  }

  @override
  Future<void> setTyping({required String matchId, required bool isTyping}) {
    if (_isDemo(matchId)) {
      return hub.chat.setTyping(matchId: matchId, isTyping: isTyping);
    }
    return remote.setTyping(matchId: matchId, isTyping: isTyping);
  }

  @override
  Stream<Map<String, DateTime>> watchTyping(String matchId) {
    if (_isDemo(matchId)) {
      return hub.chat.watchTyping(matchId);
    }
    return remote.watchTyping(matchId);
  }
}

/// Demo matches live only in memory. Unmatch/block must not hit Cloud Functions.
class OverlaySafetyRepository implements SafetyRepository {
  OverlaySafetyRepository({
    required this.remote,
    required this.hub,
  }) : _local = GraphSafetyRepository(hub.graph, hub.uidSource);

  final SafetyRepository remote;
  final DemoSocialHub hub;
  final GraphSafetyRepository _local;

  bool _isDemoMatch(String? matchId) {
    if (matchId == null || matchId.isEmpty) {
      return false;
    }
    return hub.graph.matches.containsKey(matchId) ||
        matchId.contains('mock-');
  }

  bool _isDemoUser(String userId) => DemoSocialHub.isDemoUid(userId);

  @override
  Future<void> unmatch({required String matchId}) {
    if (_isDemoMatch(matchId)) {
      return _local.unmatch(matchId: matchId);
    }
    return remote.unmatch(matchId: matchId);
  }

  @override
  Future<void> blockUser({required String userId, String? matchId}) {
    if (_isDemoUser(userId) || _isDemoMatch(matchId)) {
      return _local.blockUser(userId: userId, matchId: matchId);
    }
    return remote.blockUser(userId: userId, matchId: matchId);
  }

  @override
  Future<void> reportUser({
    required String userId,
    required String reason,
    String? matchId,
    String? messageId,
    String? description,
  }) {
    if (_isDemoUser(userId) || _isDemoMatch(matchId)) {
      return _local.reportUser(
        userId: userId,
        reason: reason,
        matchId: matchId,
        messageId: messageId,
        description: description,
      );
    }
    return remote.reportUser(
      userId: userId,
      reason: reason,
      matchId: matchId,
      messageId: messageId,
      description: description,
    );
  }

  @override
  Future<bool> isBlockedPair(String uidA, String uidB) async {
    if (_isDemoUser(uidA) || _isDemoUser(uidB)) {
      return _local.isBlockedPair(uidA, uidB);
    }
    return remote.isBlockedPair(uidA, uidB);
  }

  @override
  Stream<Set<String>> watchBlockedUserIds(String uid) {
    return remote.watchBlockedUserIds(uid);
  }
}
