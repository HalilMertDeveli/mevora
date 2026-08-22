import 'package:mevora/core/debug/agent_debug_log.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/calls/domain/models/call_session.dart';
import 'package:mevora/features/calls/domain/services/video_call_provider.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/chat/domain/repositories/chat_repository.dart';
import 'package:mevora/features/matching/data/memory/in_memory_social_graph.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';
import 'package:mevora/features/notifications/domain/models/notification_prefs.dart';
import 'package:mevora/features/safety/domain/safety_policy.dart';

class GraphMatchRepository implements MatchRepository, LikeRepository, DiscoveryExclusionSource {
  GraphMatchRepository(this.graph, this.auth);

  final InMemorySocialGraph graph;
  final AuthUidSource auth;

  String get _uid {
    final uid = auth.currentUid;
    if (uid == null) {
      throw const AuthzMissing();
    }
    return uid;
  }

  @override
  Stream<List<MatchListItem>> watchMatches(String uid) =>
      graph.watchMatches(uid);

  @override
  Future<Match?> getMatch(String matchId) async => graph.matches[matchId];

  @override
  Stream<Match?> watchMatch(String matchId) async* {
    yield graph.matches[matchId];
  }

  @override
  Future<void> markOpened(String matchId, String uid) async {
    final match = graph.matches[matchId];
    if (match == null) {
      return;
    }
    graph.matches[matchId] = match.copyWith(
      isNewFor: {...match.isNewFor, uid: false},
      unreadCounts: {...match.unreadCounts, uid: 0},
    );
  }

  @override
  Future<SwipeResultWrapper> recordSwipe({
    required String targetUserId,
    required String action,
  }) async {
    return graph.recordSwipe(
      actorUid: _uid,
      targetUserId: targetUserId,
      action: action,
    );
  }

  @override
  Stream<Set<String>> watchHiddenUserIds(String uid) async* {
    yield graph.hiddenUserIds(uid);
  }
}

class AuthzMissing implements Exception {
  const AuthzMissing();
}

class GraphChatRepository implements ChatRepository {
  GraphChatRepository(this.graph, this.auth);

  final InMemorySocialGraph graph;
  final AuthUidSource auth;

  String get _uid => auth.currentUid ?? '';

  @override
  Stream<List<ChatMessage>> watchLatest(String matchId, {int limit = 30}) {
    return graph.watchMessages(matchId);
  }

  @override
  Future<ChatPage> loadOlder({
    required String matchId,
    required ChatMessage before,
    int limit = 30,
  }) async {
    return graph.loadOlder(matchId: matchId, before: before, limit: limit);
  }

  @override
  Future<ChatMessage> sendText({
    required String matchId,
    required String receiverId,
    required String text,
  }) async {
    return graph.sendText(
      actorUid: _uid,
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
  }) async {
    onProgress?.call(1);
    final sent = graph.sendMedia(
      actorUid: _uid,
      matchId: matchId,
      receiverId: receiverId,
      type: MessageType.image,
      bytes: media.bytes,
    );
    // #region agent log
    AgentDebugLog.log(
      location: 'graph_repositories.dart:sendImage',
      message: 'demo_image_sent',
      hypothesisId: 'I1',
      data: {
        'bytesKept': sent.localMediaBytes?.length ?? 0,
        'hasUrl': sent.mediaUrl != null,
        'urlHost': Uri.tryParse(sent.mediaUrl ?? '')?.host,
      },
    );
    // #endregion
    return sent;
  }

  @override
  Future<ChatMessage> sendVoice({
    required String matchId,
    required String receiverId,
    required ChatMediaBytes media,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(1);
    return graph.sendMedia(
      actorUid: _uid,
      matchId: matchId,
      receiverId: receiverId,
      type: MessageType.voice,
      durationMs: media.durationMs,
      bytes: media.bytes,
    );
  }

  @override
  Future<void> deleteMessage({
    required String matchId,
    required String messageId,
  }) async {
    graph.deleteMessage(
      actorUid: _uid,
      matchId: matchId,
      messageId: messageId,
    );
  }

  @override
  Future<void> markDelivered(String matchId, List<ChatMessage> messages) async {}

  @override
  Future<void> markRead(String matchId, List<ChatMessage> messages) async {
    graph.markRead(actorUid: _uid, matchId: matchId, items: messages);
  }

  @override
  Future<void> setTyping({
    required String matchId,
    required bool isTyping,
  }) async {
    graph.setTyping(actorUid: _uid, matchId: matchId, isTyping: isTyping);
  }

  @override
  Stream<Map<String, DateTime>> watchTyping(String matchId) {
    return graph.watchTyping(matchId);
  }
}

class GraphSafetyRepository implements SafetyRepository {
  GraphSafetyRepository(this.graph, this.auth);

  final InMemorySocialGraph graph;
  final AuthUidSource auth;

  @override
  Future<void> unmatch({required String matchId}) async {
    graph.unmatch(actorUid: auth.currentUid ?? '', matchId: matchId);
  }

  @override
  Future<void> blockUser({required String userId, String? matchId}) async {
    graph.blockUser(actorUid: auth.currentUid ?? '', userId: userId);
  }

  @override
  Future<void> reportUser({
    required String userId,
    required String reason,
    String? matchId,
    String? messageId,
    String? description,
  }) async {
    graph.report(
      actorUid: auth.currentUid ?? '',
      userId: userId,
      reason: reason,
      matchId: matchId,
      messageId: messageId,
      description: description,
    );
  }

  @override
  Future<bool> isBlockedPair(String uidA, String uidB) async {
    return SafetyPolicy.isBlocked(
      blockIds: graph.blockIds,
      uidA: uidA,
      uidB: uidB,
    );
  }

  @override
  Stream<Set<String>> watchBlockedUserIds(String uid) async* {
    yield graph.hiddenUserIds(uid);
  }
}

class GraphCallRepository implements CallRepository {
  GraphCallRepository(this.graph, this.auth);

  final InMemorySocialGraph graph;
  final AuthUidSource auth;

  @override
  Future<CallSession> createCall({
    required String matchId,
    required String receiverId,
  }) async {
    return graph.createCall(
      actorUid: auth.currentUid ?? '',
      matchId: matchId,
      receiverId: receiverId,
    );
  }

  @override
  Future<CallSession> respond({
    required String callId,
    required bool accept,
  }) async {
    return graph.respond(
      actorUid: auth.currentUid ?? '',
      callId: callId,
      accept: accept,
    );
  }

  @override
  Future<void> end(String callId) async {
    graph.endCall(callId);
  }

  @override
  Future<void> expire(String callId) async {
    graph.endCall(callId);
  }

  @override
  Stream<List<CallSession>> watchIncoming(String uid) {
    return graph.watchIncoming(uid);
  }

  @override
  Stream<CallSession?> watchCall(String callId) {
    return graph.watchCall(callId);
  }
}

class GraphNotificationRepository implements NotificationRepository {
  GraphNotificationRepository(this.graph);

  final InMemorySocialGraph graph;

  @override
  Stream<NotificationPrefs> watchPrefs(String uid) async* {
    yield graph.prefs[uid] ?? const NotificationPrefs();
  }

  @override
  Future<NotificationPrefs> loadPrefs(String uid) async {
    return graph.prefs[uid] ?? const NotificationPrefs();
  }

  @override
  Future<void> savePrefs(String uid, NotificationPrefs prefs) async {
    graph.prefs[uid] = prefs;
  }

  @override
  Future<void> registerToken(String uid, String token) async {}

  @override
  Future<void> unregisterToken(String uid, String token) async {}
}

class GraphPresenceRepository implements PresenceRepository {
  GraphPresenceRepository(this.graph);

  final InMemorySocialGraph graph;

  @override
  Stream<PresenceWatch> watch(String uid) async* {
    yield graph.presence[uid] ??
        const PresenceWatch(updatedAt: null, hideOnlineStatus: false);
  }

  @override
  Future<void> heartbeat(String uid, {required bool hideOnlineStatus}) async {
    graph.presence[uid] = PresenceWatch(
      updatedAt: DateTime.now(),
      hideOnlineStatus: hideOnlineStatus,
    );
  }
}
