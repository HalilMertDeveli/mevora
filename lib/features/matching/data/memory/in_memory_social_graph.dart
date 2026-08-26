import 'dart:async';
import 'dart:math';

import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/calls/domain/call_state_machine.dart';
import 'package:mevora/features/calls/domain/models/call_session.dart';
import 'package:mevora/features/chat/domain/chat_policy.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/chat/domain/repositories/chat_repository.dart';
import 'package:mevora/features/matching/domain/match_engine.dart';
import 'package:mevora/features/matching/domain/models/like_record.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/features/matching/domain/models/swipe_action.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';
import 'package:mevora/features/match_score/data/datasources/memory_match_score_data_source.dart';
import 'package:mevora/features/notifications/domain/models/notification_prefs.dart';
import 'package:mevora/features/safety/domain/models/report_reason.dart';
import 'package:mevora/features/safety/domain/safety_policy.dart';

/// Trusted-backend stand-in used by tests. Mirrors Cloud Function rules:
/// clients never create matches directly.
class InMemorySocialGraph {
  InMemorySocialGraph({
    this.now,
    MemoryMatchScoreDataSource? matchScore,
  }) : matchScore = matchScore ?? MemoryMatchScoreDataSource();

  DateTime Function()? now;
  final MemoryMatchScoreDataSource matchScore;

  final Map<String, LikeRecord> likes = {};
  final Map<String, Match> matches = {};
  final Map<String, List<ChatMessage>> messages = {};
  final Map<String, Map<String, DateTime>> typing = {};
  final Set<String> blockIds = {};
  final List<UserReport> reports = [];
  final Map<String, CallSession> calls = {};
  final List<CallHistoryRecord> history = [];
  final Map<String, NotificationPrefs> prefs = {};
  final Map<String, PresenceWatch> presence = {};
  final Map<String, _Profile> profiles = {};

  final _matchControllers = <String, StreamController<List<MatchListItem>>>{};
  final _messageControllers = <String, StreamController<List<ChatMessage>>>{};
  final _typingControllers =
      <String, StreamController<Map<String, DateTime>>>{};
  final _incomingControllers = <String, StreamController<List<CallSession>>>{};
  final _callControllers = <String, StreamController<CallSession?>>{};
  final _presenceControllers = <String, StreamController<PresenceWatch>>{};

  DateTime get _now => now?.call() ?? DateTime.now();

  void seedProfile(String uid, {required String name, String? photoUrl}) {
    profiles[uid] = _Profile(name: name, photoUrl: photoUrl);
    matchScore.ensureUser(uid);
  }

  SwipeResultWrapper recordSwipe({
    required String actorUid,
    required String targetUserId,
    required String action,
  }) {
    if (actorUid.isEmpty) {
      throw const AuthzException('unauthenticated', code: 'unauthenticated');
    }
    if (!MatchEngine.isValidPair(actorUid, targetUserId)) {
      throw const ValidationException('self');
    }
    if (SafetyPolicy.isBlocked(
      blockIds: blockIds,
      uidA: actorUid,
      uidB: targetUserId,
    )) {
      throw const AuthzException('blocked', code: 'blocked');
    }
    final likeId = MatchEngine.likeId(
      fromUserId: actorUid,
      toUserId: targetUserId,
    );
    if (likes.containsKey(likeId)) {
      throw const ValidationException('already-swiped');
    }
    final swipe = SwipeActionX.fromFirestore(action);
    final forward = MatchEngine.buildLike(
      fromUserId: actorUid,
      toUserId: targetUserId,
      action: swipe,
      createdAt: _now,
    );
    likes[likeId] = forward;
    final reverseId = MatchEngine.likeId(
      fromUserId: targetUserId,
      toUserId: actorUid,
    );
    final reverse = likes[reverseId];
    final matchId = MatchEngine.matchId(actorUid, targetUserId);
    final existing = matches[matchId];
    final shouldCreate = MatchEngine.shouldCreateMatch(
      forward: forward,
      reverse: reverse,
      blocked: false,
      existingActiveMatch: existing?.isActive ?? false,
    );
    Match? created;
    if (shouldCreate) {
      created = MatchEngine.buildMatch(
        uidA: actorUid,
        uidB: targetUserId,
        createdAt: _now,
        names: {
          actorUid: profiles[actorUid]?.name ?? 'Mevora',
          targetUserId: profiles[targetUserId]?.name ?? 'Mevora',
        },
        photos: {
          if (profiles[actorUid]?.photoUrl != null)
            actorUid: profiles[actorUid]!.photoUrl!,
          if (profiles[targetUserId]?.photoUrl != null)
            targetUserId: profiles[targetUserId]!.photoUrl!,
        },
      );
      matches[matchId] = created;
      messages[matchId] = [];
      matchScore.recordMatchCreated(
        matchId: matchId,
        userIds: created.userIds,
        matchedAt: created.createdAt,
      );
      _emitMatches(actorUid);
      _emitMatches(targetUserId);
    }
    return SwipeResultWrapper(matched: created != null, match: created);
  }

  List<MatchListItem> listMatches(String uid) {
    final items = matches.values
        .where((match) => match.isActive && match.isParticipant(uid))
        .map((match) {
          final other = match.otherUserId(uid);
          return MatchListItem(
            match: match,
            otherUserId: other,
            name: match.otherName(uid),
            photoUrl: match.otherPhoto(uid),
          );
        })
        .toList()
      ..sort((a, b) {
        final aTime = a.match.lastMessageAt ?? a.match.createdAt;
        final bTime = b.match.lastMessageAt ?? b.match.createdAt;
        return bTime.compareTo(aTime);
      });
    return items;
  }

  Stream<List<MatchListItem>> watchMatches(String uid) {
    final controller = _matchControllers.putIfAbsent(
      uid,
      () => StreamController<List<MatchListItem>>.broadcast(),
    );
    scheduleMicrotask(() => controller.add(listMatches(uid)));
    return controller.stream;
  }

  ChatMessage sendText({
    required String actorUid,
    required String matchId,
    required String receiverId,
    required String text,
  }) {
    final match = _requireActiveMatch(matchId, actorUid, receiverId);
    if (!ChatPolicy.canSendMessage(
      match: match,
      senderId: actorUid,
      receiverId: receiverId,
      blocked: SafetyPolicy.isBlocked(
        blockIds: blockIds,
        uidA: actorUid,
        uidB: receiverId,
      ),
    )) {
      throw const AuthzException('blocked', code: 'blocked');
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('empty');
    }
    final message = ChatMessage(
      id: 'm${_now.microsecondsSinceEpoch}${Random().nextInt(999)}',
      senderId: actorUid,
      receiverId: receiverId,
      text: trimmed,
      type: MessageType.text,
      createdAt: _now,
      status: MessageStatus.sent,
    );
    messages.putIfAbsent(matchId, () => []).add(message);
    _afterSend(
      match: match,
      senderId: actorUid,
      receiverId: receiverId,
      preview: trimmed,
      at: message.createdAt,
    );
    return message;
  }

  ChatMessage sendMedia({
    required String actorUid,
    required String matchId,
    required String receiverId,
    required MessageType type,
    int? durationMs,
    List<int>? bytes,
  }) {
    final match = _requireActiveMatch(matchId, actorUid, receiverId);
    if (!ChatPolicy.canSendMessage(
      match: match,
      senderId: actorUid,
      receiverId: receiverId,
      blocked: SafetyPolicy.isBlocked(
        blockIds: blockIds,
        uidA: actorUid,
        uidB: receiverId,
      ),
    )) {
      throw const AuthzException('blocked', code: 'blocked');
    }
    final messageId = 'm${_now.microsecondsSinceEpoch}${Random().nextInt(999)}';
    final path = ChatMediaArchitecture.storagePath(
      senderUid: actorUid,
      matchId: matchId,
      messageId: messageId,
    );
    final message = ChatMessage(
      id: messageId,
      senderId: actorUid,
      receiverId: receiverId,
      text: '',
      type: type,
      createdAt: _now,
      status: MessageStatus.sent,
      imageStoragePath: type == MessageType.image ? path : null,
      voiceStoragePath: type == MessageType.voice ? path : null,
      mediaUrl: null,
      durationMs: durationMs,
      localMediaBytes: bytes == null || bytes.isEmpty
          ? null
          : List<int>.unmodifiable(bytes),
    );
    messages.putIfAbsent(matchId, () => []).add(message);
    _afterSend(
      match: match,
      senderId: actorUid,
      receiverId: receiverId,
      preview: type == MessageType.image ? '📷' : '🎤',
      at: message.createdAt,
    );
    return message;
  }

  void deleteMessage({
    required String actorUid,
    required String matchId,
    required String messageId,
  }) {
    final current = messages[matchId];
    if (current == null) {
      return;
    }
    final target = current.cast<ChatMessage?>().firstWhere(
      (item) => item?.id == messageId,
      orElse: () => null,
    );
    if (target == null) {
      return;
    }
    if (!ChatPolicy.canDeleteOwnMessage(message: target, uid: actorUid)) {
      throw const AuthzException('not-allowed', code: 'permission-denied');
    }
    messages[matchId] = [
      for (final item in current)
        if (item.id == messageId)
          item.copyWith(deleted: true, text: '', mediaUrl: '')
        else
          item,
    ];
    _emitMessages(matchId);
  }

  void _afterSend({
    required Match match,
    required String senderId,
    required String receiverId,
    required String preview,
    required DateTime at,
  }) {
    final unread = Map<String, int>.from(match.unreadCounts);
    unread[receiverId] = (unread[receiverId] ?? 0) + 1;
    matches[match.id] = Match(
      id: match.id,
      userIds: match.userIds,
      createdAt: match.createdAt,
      isActive: match.isActive,
      lastMessage: preview,
      lastMessageAt: at,
      unmatchedBy: match.unmatchedBy,
      unmatchedAt: match.unmatchedAt,
      unreadCounts: unread,
      isNewFor: {for (final id in match.userIds) id: false},
      participantNames: match.participantNames,
      participantPhotos: match.participantPhotos,
      source: match.source,
    );
    matchScore.recordMessage(
      matchId: match.id,
      senderId: senderId,
      now: at,
    );
    _emitMessages(match.id);
    _emitMatches(match.userIds[0]);
    _emitMatches(match.userIds[1]);
  }

  List<ChatMessage> latestMessages(String matchId, {int limit = 30}) {
    final all = messages[matchId] ?? const <ChatMessage>[];
    if (all.length <= limit) {
      return List<ChatMessage>.from(all);
    }
    return all.sublist(all.length - limit);
  }

  ChatPage loadOlder({
    required String matchId,
    required ChatMessage before,
    int limit = 30,
  }) {
    final all = messages[matchId] ?? const <ChatMessage>[];
    final index = all.indexWhere((item) => item.id == before.id);
    if (index <= 0) {
      return const ChatPage(messages: [], hasMore: false);
    }
    final start = (index - limit) < 0 ? 0 : index - limit;
    return ChatPage(
      messages: all.sublist(start, index),
      hasMore: start > 0,
    );
  }

  void markRead({
    required String actorUid,
    required String matchId,
    required List<ChatMessage> items,
  }) {
    final current = messages[matchId];
    if (current == null) {
      return;
    }
    messages[matchId] = current.map((message) {
      if (message.receiverId != actorUid || message.isRead) {
        return message;
      }
      if (items.every((item) => item.id != message.id)) {
        return message;
      }
      return message.copyWith(
        status: MessageStatus.read,
        isRead: true,
        readAt: _now,
      );
    }).toList();
    final match = matches[matchId];
    if (match != null) {
      final unread = Map<String, int>.from(match.unreadCounts);
      unread[actorUid] = 0;
      matches[matchId] = Match(
        id: match.id,
        userIds: match.userIds,
        createdAt: match.createdAt,
        isActive: match.isActive,
        lastMessage: match.lastMessage,
        lastMessageAt: match.lastMessageAt,
        unmatchedBy: match.unmatchedBy,
        unmatchedAt: match.unmatchedAt,
        unreadCounts: unread,
        isNewFor: match.isNewFor,
        participantNames: match.participantNames,
        participantPhotos: match.participantPhotos,
        source: match.source,
      );
      _emitMatches(match.userIds[0]);
      _emitMatches(match.userIds[1]);
    }
    _emitMessages(matchId);
  }

  void setTyping({
    required String actorUid,
    required String matchId,
    required bool isTyping,
  }) {
    final current = Map<String, DateTime>.from(typing[matchId] ?? {});
    if (isTyping) {
      current[actorUid] = _now;
    } else {
      current.remove(actorUid);
    }
    typing[matchId] = current;
    _typingControllers[matchId]?.add(current);
  }

  void unmatch({
    required String actorUid,
    required String matchId,
    String reason = 'unmatch',
  }) {
    final match = matches[matchId];
    if (match == null || !match.isParticipant(actorUid)) {
      throw const AuthzException('not-matched', code: 'not-matched');
    }
    matches[matchId] = Match(
      id: match.id,
      userIds: match.userIds,
      createdAt: match.createdAt,
      isActive: false,
      lastMessage: match.lastMessage,
      lastMessageAt: match.lastMessageAt,
      unmatchedBy: actorUid,
      unmatchedAt: _now,
      unreadCounts: match.unreadCounts,
      isNewFor: match.isNewFor,
      participantNames: match.participantNames,
      participantPhotos: match.participantPhotos,
      source: match.source,
    );
    matchScore.recordMatchEnded(
      matchId: matchId,
      endedBy: actorUid,
      reason: reason,
      userIds: match.userIds,
    );
    _emitMatches(match.userIds[0]);
    _emitMatches(match.userIds[1]);
    _endLiveCalls(matchId);
  }

  void blockUser({required String actorUid, required String userId}) {
    blockIds.add(SafetyPolicy.blockId(blockerId: actorUid, blockedUserId: userId));
    final matchId = MatchEngine.matchId(actorUid, userId);
    if (matches.containsKey(matchId)) {
      unmatch(actorUid: actorUid, matchId: matchId, reason: 'block');
    }
  }

  void _endLiveCalls(String matchId) {
    final live = calls.values.where(
      (call) =>
          call.matchId == matchId && !CallStateMachine.isTerminal(call.lifecycle),
    );
    for (final call in live) {
      calls[call.id] = call.copyWith(lifecycle: CallLifecycle.ended);
      _emitCall(calls[call.id]!);
    }
  }

  void _emitCall(CallSession call) {
    _callControllers[call.id]?.add(call);
    _incomingControllers[call.receiverId]?.add(
      calls.values
          .where((item) => item.receiverId == call.receiverId)
          .toList(growable: false),
    );
  }

  void report({
    required String actorUid,
    required String userId,
    required String reason,
    String? matchId,
    String? messageId,
    String? description,
  }) {
    reports.add(
      UserReport(
        id: 'r${reports.length + 1}',
        reporterId: actorUid,
        reportedUserId: userId,
        reason: ReportReason.values.firstWhere(
          (item) => item.firestoreValue == reason,
          orElse: () => ReportReason.other,
        ),
        createdAt: _now,
        status: 'open',
        matchId: matchId,
        messageId: messageId,
        description: description,
      ),
    );
  }

  CallSession createCall({
    required String actorUid,
    required String matchId,
    required String receiverId,
  }) {
    final match = _requireActiveMatch(matchId, actorUid, receiverId);
    if (SafetyPolicy.isBlocked(
      blockIds: blockIds,
      uidA: actorUid,
      uidB: receiverId,
    )) {
      throw const AuthzException('blocked', code: 'blocked');
    }
    if (!CallPolicy.canStartCall(
      matchActive: match.isActive,
      blocked: false,
      isParticipant: true,
      receiverBusy: calls.values.any(
        (call) =>
            (call.receiverId == receiverId || call.callerId == receiverId) &&
            !CallStateMachine.isTerminal(call.lifecycle),
      ),
    )) {
      throw const AuthzException('busy', code: 'busy');
    }
    final session = CallSession(
      id: 'c${_now.microsecondsSinceEpoch}',
      matchId: matchId,
      callerId: actorUid,
      receiverId: receiverId,
      lifecycle: CallLifecycle.calling,
      createdAt: _now,
      livekitUrl: 'wss://example.livekit.cloud',
      token: 'short-lived-test-token',
      roomName: 'call_test',
      remoteName: match.otherName(actorUid),
      remotePhotoUrl: match.otherPhoto(actorUid),
    );
    calls[session.id] = session;
    _emitCall(session);
    return session;
  }

  CallSession respond({
    required String actorUid,
    required String callId,
    required bool accept,
  }) {
    final call = calls[callId];
    if (call == null || call.receiverId != actorUid) {
      throw const AuthzException('not-found', code: 'not-found');
    }
    final next = accept ? CallLifecycle.connecting : CallLifecycle.declined;
    final updated = call.copyWith(lifecycle: next);
    calls[callId] = updated;
    _emitCall(updated);
    if (!accept) {
      history.add(
        CallHistoryRecord(
          id: callId,
          callerId: call.callerId,
          receiverId: call.receiverId,
          matchId: call.matchId,
          type: 'video',
          status: CallHistoryStatus.declined,
          startedAt: call.createdAt,
          endedAt: _now,
        ),
      );
    }
    return updated.copyWith(
      livekitUrl: call.livekitUrl,
      token: 'short-lived-test-token',
      roomName: call.roomName,
    );
  }

  void endCall(String callId, {CallLifecycle lifecycle = CallLifecycle.ended}) {
    final call = calls[callId];
    if (call == null) {
      return;
    }
    final updated = call.copyWith(lifecycle: lifecycle);
    calls[callId] = updated;
    _emitCall(updated);
  }

  Match _requireActiveMatch(String matchId, String uid, String otherUid) {
    final match = matches[matchId];
    if (match == null || !match.isParticipant(uid)) {
      throw const AuthzException('not-matched', code: 'not-matched');
    }
    if (!match.isActive) {
      throw const AuthzException('inactive-match', code: 'inactive-match');
    }
    if (MatchEngine.matchId(uid, otherUid) != matchId) {
      throw const AuthzException('not-matched', code: 'not-matched');
    }
    return match;
  }

  void _emitMatches(String uid) {
    _matchControllers[uid]?.add(listMatches(uid));
  }

  void _emitMessages(String matchId) {
    _messageControllers[matchId]?.add(latestMessages(matchId));
  }

  Stream<List<ChatMessage>> watchMessages(String matchId) {
    final controller = _messageControllers.putIfAbsent(
      matchId,
      () => StreamController<List<ChatMessage>>.broadcast(),
    );
    scheduleMicrotask(() => controller.add(latestMessages(matchId)));
    return controller.stream;
  }

  Stream<Map<String, DateTime>> watchTyping(String matchId) {
    final controller = _typingControllers.putIfAbsent(
      matchId,
      () => StreamController<Map<String, DateTime>>.broadcast(),
    );
    scheduleMicrotask(() => controller.add(typing[matchId] ?? {}));
    return controller.stream;
  }

  Stream<PresenceWatch> watchPresence(String uid) {
    final controller = _presenceControllers.putIfAbsent(
      uid,
      () => StreamController<PresenceWatch>.broadcast(),
    );
    scheduleMicrotask(
      () => controller.add(
        presence[uid] ?? const PresenceWatch(updatedAt: null),
      ),
    );
    return controller.stream;
  }

  void emitPresence(String uid) {
    _presenceControllers[uid]?.add(
      presence[uid] ?? const PresenceWatch(updatedAt: null),
    );
  }

  Stream<List<CallSession>> watchIncoming(String uid) {
    final controller = _incomingControllers.putIfAbsent(
      uid,
      () => StreamController<List<CallSession>>.broadcast(),
    );
    scheduleMicrotask(
      () => controller.add(
        calls.values.where((call) => call.receiverId == uid).toList(),
      ),
    );
    return controller.stream;
  }

  Stream<CallSession?> watchCall(String callId) {
    final controller = _callControllers.putIfAbsent(
      callId,
      () => StreamController<CallSession?>.broadcast(),
    );
    scheduleMicrotask(() => controller.add(calls[callId]));
    return controller.stream;
  }

  Set<String> hiddenUserIds(String uid) {
    final hidden = <String>{};
    for (final blockId in blockIds) {
      final parts = blockId.split('_');
      if (parts.length >= 2 && parts.first == uid) {
        hidden.add(parts.sublist(1).join('_'));
      }
    }
    for (final match in matches.values) {
      if (match.isParticipant(uid) && !match.isActive) {
        hidden.add(match.otherUserId(uid));
      }
    }
    return hidden;
  }
}

class _Profile {
  const _Profile({required this.name, this.photoUrl});

  final String name;
  final String? photoUrl;
}

class MutableAuthUidSource implements AuthUidSource {
  MutableAuthUidSource(this._uid);

  String? _uid;
  final _controller = StreamController<String?>.broadcast();

  set uid(String? value) {
    _uid = value;
    _controller.add(value);
  }

  @override
  String? get currentUid => _uid;

  @override
  Stream<String?> watchUid() => _controller.stream;
}
