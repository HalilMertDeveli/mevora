import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/calls/domain/models/call_session.dart';
import 'package:mevora/features/calls/domain/services/video_call_provider.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/chat/domain/repositories/chat_repository.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';
import 'package:mevora/features/notifications/data/datasources/firebase_messaging_data_source.dart';
import 'package:mevora/features/notifications/domain/models/notification_prefs.dart';
import 'package:mevora/features/safety/domain/safety_policy.dart';

DateTime? _time(Object? value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  return null;
}

Match _matchFrom(DocumentSnapshot<Map<String, dynamic>> snap) {
  final data = snap.data() ?? const <String, dynamic>{};
  final userIds = (data['userIds'] as List<dynamic>? ?? const [])
      .map((item) => item.toString())
      .toList(growable: false);
  return Match(
    id: snap.id,
    userIds: userIds,
    createdAt: _time(data['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    isActive: data['isActive'] as bool? ?? false,
    lastMessage: data['lastMessage'] as String?,
    lastMessageAt: _time(data['lastMessageAt']),
    unmatchedBy: data['unmatchedBy'] as String?,
    unmatchedAt: _time(data['unmatchedAt']),
    unreadCounts: _stringIntMap(data['unreadCounts']),
    isNewFor: _stringBoolMap(data['isNewFor']),
    participantNames: _stringStringMap(data['participantNames']),
    participantPhotos: _stringStringMap(data['participantPhotos']),
  );
}

Map<String, int> _stringIntMap(Object? value) {
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), (item as num?)?.toInt() ?? 0));
  }
  return const {};
}

Map<String, bool> _stringBoolMap(Object? value) {
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item == true));
  }
  return const {};
}

Map<String, String> _stringStringMap(Object? value) {
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item.toString()));
  }
  return const {};
}

class FirebaseMatchRepository implements MatchRepository, LikeRepository, DiscoveryExclusionSource {
  FirebaseMatchRepository({
    required this.callable,
    required this.uidSource,
    FirebaseFirestore? firestore,
  }) : _db = firestore ?? FirebaseFirestore.instance;

  final BackendCallable callable;
  final AuthUidSource uidSource;
  final FirebaseFirestore _db;

  @override
  Stream<List<MatchListItem>> watchMatches(String uid) {
    return _db
        .collection(FirestorePaths.matches)
        .where('userIds', arrayContains: uid)
        .where('isActive', isEqualTo: true)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snap) {
          return snap.docs.map((doc) {
            final match = _matchFrom(doc);
            return MatchListItem(
              match: match,
              otherUserId: match.otherUserId(uid),
              name: match.otherName(uid),
              photoUrl: match.otherPhoto(uid),
            );
          }).toList(growable: false);
        });
  }

  @override
  Future<Match?> getMatch(String matchId) async {
    final snap = await _db.doc(FirestorePaths.match(matchId)).get();
    if (!snap.exists) {
      return null;
    }
    return _matchFrom(snap);
  }

  @override
  Stream<Match?> watchMatch(String matchId) {
    return _db.doc(FirestorePaths.match(matchId)).snapshots().map((snap) {
      return snap.exists ? _matchFrom(snap) : null;
    });
  }

  @override
  Future<void> markOpened(String matchId, String uid) async {
    await _db.doc(FirestorePaths.match(matchId)).update({
      'isNewFor.$uid': false,
      'unreadCounts.$uid': 0,
    });
  }

  @override
  Future<SwipeResultWrapper> recordSwipe({
    required String targetUserId,
    required String action,
  }) async {
    final data = await callable.invoke('recordSwipe', {
      'targetUserId': targetUserId,
      'action': action,
    });
    final matched = data['matched'] == true;
    Match? match;
    final matchId = data['matchId'] as String?;
    if (matched && matchId != null) {
      match = await getMatch(matchId);
    }
    return SwipeResultWrapper(matched: matched, match: match);
  }

  @override
  Stream<Set<String>> watchHiddenUserIds(String uid) {
    final blocks = _db
        .collection(FirestorePaths.blocks)
        .where('blockerId', isEqualTo: uid)
        .snapshots();
    return blocks.map((snap) {
      return snap.docs
          .map((doc) => doc.data()['blockedUserId'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
    });
  }
}

class FirebaseChatRepository implements ChatRepository {
  FirebaseChatRepository({
    required this.uidSource,
    FirebaseFirestore? firestore,
  }) : _db = firestore ?? FirebaseFirestore.instance;

  final AuthUidSource uidSource;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _col(String matchId) {
    return _db.collection(FirestorePaths.matchMessages(matchId));
  }

  ChatMessage _from(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? const <String, dynamic>{};
    return ChatMessage(
      id: snap.id,
      senderId: data['senderId'] as String? ?? '',
      receiverId: data['receiverId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      type: MessageTypeX.fromFirestore(data['type'] as String?),
      createdAt: _time(data['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      status: MessageStatusX.fromFirestore(data['status'] as String?),
      isRead: data['isRead'] as bool? ?? false,
      readAt: _time(data['readAt']),
      imageStoragePath: data['imageStoragePath'] as String?,
    );
  }

  @override
  Stream<List<ChatMessage>> watchLatest(String matchId, {int limit = 30}) {
    return _col(matchId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.reversed.map(_from).toList());
  }

  @override
  Future<ChatPage> loadOlder({
    required String matchId,
    required ChatMessage before,
    int limit = 30,
  }) async {
    final cursor = await _col(matchId).doc(before.id).get();
    final snap = await _col(matchId)
        .orderBy('createdAt', descending: true)
        .startAfterDocument(cursor)
        .limit(limit)
        .get();
    final items = snap.docs.reversed.map(_from).toList(growable: false);
    return ChatPage(messages: items, hasMore: snap.docs.length == limit);
  }

  @override
  Future<ChatMessage> sendText({
    required String matchId,
    required String receiverId,
    required String text,
  }) async {
    final uid = uidSource.currentUid;
    if (uid == null) {
      throw const AuthzException('unauthenticated', code: 'unauthenticated');
    }
    final doc = _col(matchId).doc();
    await doc.set({
      'senderId': uid,
      'receiverId': receiverId,
      'text': text.trim(),
      'type': MessageType.text.name,
      'createdAt': FieldValue.serverTimestamp(),
      'status': MessageStatus.sent.name,
      'isRead': false,
    });
    final snap = await doc.get();
    return _from(snap);
  }

  @override
  Future<void> markDelivered(String matchId, List<ChatMessage> messages) async {
    final batch = _db.batch();
    for (final message in messages) {
      if (message.status != MessageStatus.sent) {
        continue;
      }
      batch.update(_col(matchId).doc(message.id), {
        'status': MessageStatus.delivered.name,
      });
    }
    await batch.commit();
  }

  @override
  Future<void> markRead(String matchId, List<ChatMessage> messages) async {
    final batch = _db.batch();
    for (final message in messages) {
      batch.update(_col(matchId).doc(message.id), {
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
        'status': MessageStatus.read.name,
      });
    }
    if (messages.isNotEmpty) {
      await batch.commit();
    }
  }

  @override
  Future<void> setTyping({
    required String matchId,
    required bool isTyping,
  }) async {
    final uid = uidSource.currentUid;
    if (uid == null) {
      return;
    }
    await _db.doc(FirestorePaths.matchTyping(matchId)).set({
      uid: isTyping ? FieldValue.serverTimestamp() : FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  @override
  Stream<Map<String, DateTime>> watchTyping(String matchId) {
    return _db.doc(FirestorePaths.matchTyping(matchId)).snapshots().map((snap) {
      final data = snap.data() ?? const <String, dynamic>{};
      return {
        for (final entry in data.entries)
          if (_time(entry.value) != null) entry.key: _time(entry.value)!,
      };
    });
  }
}

class FirebaseSafetyRepository implements SafetyRepository {
  FirebaseSafetyRepository({
    required this.callable,
    required this.uidSource,
    FirebaseFirestore? firestore,
  }) : _db = firestore ?? FirebaseFirestore.instance;

  final BackendCallable callable;
  final AuthUidSource uidSource;
  final FirebaseFirestore _db;

  @override
  Future<void> unmatch({required String matchId}) {
    return callable.invoke('unmatchUser', {'matchId': matchId});
  }

  @override
  Future<void> blockUser({required String userId, String? matchId}) {
    return callable.invoke('blockUser', {'userId': userId, 'matchId': matchId});
  }

  @override
  Future<void> reportUser({
    required String userId,
    required String reason,
    String? matchId,
    String? messageId,
    String? description,
  }) {
    return callable.invoke('reportUser', {
      'userId': userId,
      'reason': reason,
      'matchId': matchId,
      'messageId': messageId,
      'description': description,
    });
  }

  @override
  Future<bool> isBlockedPair(String uidA, String uidB) async {
    if (uidA.isEmpty || uidB.isEmpty || uidA == uidB) {
      return false;
    }
    final docs = await Future.wait([
      _db.doc(FirestorePaths.block(SafetyPolicy.blockId(blockerId: uidA, blockedUserId: uidB))).get(),
      _db.doc(FirestorePaths.block(SafetyPolicy.blockId(blockerId: uidB, blockedUserId: uidA))).get(),
      _db.doc(FirestorePaths.blockedUser(uidA, uidB)).get(),
      _db.doc(FirestorePaths.blockedUser(uidB, uidA)).get(),
    ]);
    return docs.any((doc) => doc.exists);
  }

  @override
  Stream<Set<String>> watchBlockedUserIds(String uid) {
    return _db
        .collection(FirestorePaths.blocks)
        .where('blockerId', isEqualTo: uid)
        .snapshots()
        .map((snap) {
          return snap.docs
              .map((doc) => doc.data()['blockedUserId'] as String? ?? '')
              .where((id) => id.isNotEmpty)
              .toSet();
        });
  }
}

class FirebaseCallRepository implements CallRepository {
  FirebaseCallRepository({
    required this.callable,
    required this.uidSource,
    FirebaseFirestore? firestore,
  }) : _db = firestore ?? FirebaseFirestore.instance;

  final BackendCallable callable;
  final AuthUidSource uidSource;
  final FirebaseFirestore _db;

  CallSession _from(DocumentSnapshot<Map<String, dynamic>> snap, {Map<String, dynamic>? extra}) {
    final data = {...?snap.data(), ...?extra};
    return CallSession(
      id: snap.id,
      matchId: data['matchId'] as String? ?? '',
      callerId: data['callerId'] as String? ?? '',
      receiverId: data['receiverId'] as String? ?? '',
      lifecycle: _lifecycle(data['status'] as String?),
      createdAt: _time(data['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      livekitUrl: data['url'] as String?,
      token: data['token'] as String?,
      roomName: data['roomName'] as String?,
      remoteName: data['remoteName'] as String?,
      remotePhotoUrl: data['remotePhotoUrl'] as String?,
    );
  }

  CallLifecycle _lifecycle(String? status) {
    return switch (status) {
      'ringing' => CallLifecycle.ringing,
      'calling' => CallLifecycle.calling,
      'connecting' => CallLifecycle.connecting,
      'connected' => CallLifecycle.connected,
      'declined' => CallLifecycle.declined,
      'busy' => CallLifecycle.busy,
      'failed' => CallLifecycle.failed,
      'ended' || 'missed' => CallLifecycle.ended,
      _ => CallLifecycle.idle,
    };
  }

  @override
  Future<CallSession> createCall({
    required String matchId,
    required String receiverId,
  }) async {
    final data = await callable.invoke('createVideoCall', {
      'matchId': matchId,
      'receiverId': receiverId,
    });
    return CallSession(
      id: data['callId'] as String? ?? '',
      matchId: matchId,
      callerId: uidSource.currentUid ?? '',
      receiverId: receiverId,
      lifecycle: CallLifecycle.calling,
      createdAt: DateTime.now(),
      livekitUrl: data['url'] as String?,
      token: data['token'] as String?,
      roomName: data['roomName'] as String?,
    );
  }

  @override
  Future<CallSession> respond({
    required String callId,
    required bool accept,
  }) async {
    final data = await callable.invoke('respondToVideoCall', {
      'callId': callId,
      'accept': accept,
    });
    return CallSession(
      id: callId,
      matchId: data['matchId'] as String? ?? '',
      callerId: data['callerId'] as String? ?? '',
      receiverId: uidSource.currentUid ?? '',
      lifecycle: accept ? CallLifecycle.connecting : CallLifecycle.declined,
      createdAt: DateTime.now(),
      livekitUrl: data['url'] as String?,
      token: data['token'] as String?,
      roomName: data['roomName'] as String?,
    );
  }

  @override
  Future<void> end(String callId) {
    return callable.invoke('endVideoCall', {'callId': callId});
  }

  @override
  Future<void> expire(String callId) {
    return callable.invoke('expireVideoCall', {'callId': callId});
  }

  @override
  Stream<List<CallSession>> watchIncoming(String uid) {
    return _db
        .collection(FirestorePaths.calls)
        .where('receiverId', isEqualTo: uid)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .map((snap) => snap.docs.map(_from).toList(growable: false));
  }
}

class FirebasePresenceRepository implements PresenceRepository {
  FirebasePresenceRepository([FirebaseFirestore? firestore])
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  @override
  Stream<PresenceWatch> watch(String uid) {
    return _db.doc(FirestorePaths.presence(uid)).snapshots().map((snap) {
      final data = snap.data() ?? const <String, dynamic>{};
      return PresenceWatch(
        updatedAt: _time(data['updatedAt']),
        hideOnlineStatus: data['hideOnlineStatus'] == true,
      );
    });
  }

  @override
  Future<void> heartbeat(String uid, {required bool hideOnlineStatus}) {
    return _db.doc(FirestorePaths.presence(uid)).set({
      'updatedAt': FieldValue.serverTimestamp(),
      'hideOnlineStatus': hideOnlineStatus,
    }, SetOptions(merge: true));
  }
}

class FirebaseNotificationRepository implements NotificationRepository {
  FirebaseNotificationRepository({
    FirebaseFirestore? firestore,
    FirebaseMessagingDataSource? messaging,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _messaging = messaging ??
           FirebaseMessagingDataSource(firestore: firestore);

  final FirebaseFirestore _db;
  final FirebaseMessagingDataSource _messaging;

  NotificationPrefs _prefs(Map<String, dynamic>? data) {
    return NotificationPrefs(
      messageNotifications: data?['messageNotifications'] as bool? ?? true,
      matchNotifications: data?['matchNotifications'] as bool? ?? true,
      hideOnlineStatus: data?['hideOnlineStatus'] as bool? ?? false,
    );
  }

  @override
  Stream<NotificationPrefs> watchPrefs(String uid) {
    return _db.doc(FirestorePaths.notificationSettings(uid)).snapshots().map(
      (snap) => _prefs(snap.data()),
    );
  }

  @override
  Future<NotificationPrefs> loadPrefs(String uid) async {
    final snap = await _db.doc(FirestorePaths.notificationSettings(uid)).get();
    return _prefs(snap.data());
  }

  @override
  Future<void> savePrefs(String uid, NotificationPrefs prefs) {
    return _db.doc(FirestorePaths.notificationSettings(uid)).set({
      'messageNotifications': prefs.messageNotifications,
      'matchNotifications': prefs.matchNotifications,
      'hideOnlineStatus': prefs.hideOnlineStatus,
    }, SetOptions(merge: true));
  }

  @override
  Future<void> registerToken(String uid, String token) {
    return _messaging.registerDevice(uid: uid, token: token);
  }

  @override
  Future<void> unregisterToken(String uid, String token) {
    return _messaging.unregisterDevice(uid: uid, token: token);
  }
}
