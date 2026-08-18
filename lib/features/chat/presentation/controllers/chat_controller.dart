import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/errors/social_error_mapper.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/chat/domain/chat_policy.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/chat/domain/repositories/chat_repository.dart';
import 'package:mevora/features/chat/presentation/chat_strings.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/presence_status.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';
import 'package:mevora/features/safety/domain/safety_policy.dart';

class ChatController extends ChangeNotifier {
  ChatController({
    required this.matchId,
    required ChatRepository chatRepository,
    required MatchRepository matchRepository,
    required SafetyRepository safetyRepository,
    required PresenceRepository presenceRepository,
    required AuthUidSource uidSource,
  }) : _chat = chatRepository,
       _matches = matchRepository,
       _safety = safetyRepository,
       _presence = presenceRepository,
       _uidSource = uidSource;

  final String matchId;
  final ChatRepository _chat;
  final MatchRepository _matches;
  final SafetyRepository _safety;
  final PresenceRepository _presence;
  final AuthUidSource _uidSource;

  final List<ChatMessage> messages = [];
  Match? match;
  PresenceStatus presence = PresenceStatus.offline;
  String? typingUid;
  String? error;
  bool sending = false;
  bool loadingOlder = false;
  bool hasMore = true;
  bool blocked = false;

  StreamSubscription<List<ChatMessage>>? _messageSub;
  StreamSubscription<Map<String, DateTime>>? _typingSub;
  StreamSubscription<PresenceWatch>? _presenceSub;
  Timer? _typingDebounce;
  bool _typingSent = false;

  String? get uid => _uidSource.currentUid;

  String get otherUid {
    final current = uid;
    final currentMatch = match;
    if (current == null || currentMatch == null) {
      return '';
    }
    return currentMatch.otherUserId(current);
  }

  String get otherName {
    final current = uid;
    if (current == null || match == null) {
      return '';
    }
    return match!.otherName(current);
  }

  bool get canChat =>
      match != null &&
      match!.isActive &&
      !blocked &&
      uid != null;

  bool get canCall => canChat;

  Future<void> start() async {
    final current = uid;
    if (current == null) {
      error = ChatStrings.needSignIn;
      notifyListeners();
      return;
    }
    match = await _matches.getMatch(matchId);
    blocked = await _safety.isBlockedPair(current, otherUid);
    await _matches.markOpened(matchId, current);
    _messageSub = _chat.watchLatest(matchId).listen((value) {
      messages
        ..clear()
        ..addAll(value);
      unawaited(_acknowledge(value));
      notifyListeners();
    });
    _typingSub = _chat.watchTyping(matchId).listen((value) {
      final other = otherUid;
      final at = value[other];
      typingUid = ChatPolicy.isTypingFresh(at) ? other : null;
      notifyListeners();
    });
    _presenceSub = _presence.watch(otherUid).listen((value) {
      presence = PresenceStatusX.fromUpdatedAt(
        updatedAt: value.updatedAt,
        hideOnlineStatus: value.hideOnlineStatus,
      );
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> _acknowledge(List<ChatMessage> value) async {
    final current = uid;
    if (current == null) {
      return;
    }
    final incoming = value
        .where((message) => message.receiverId == current && !message.isRead)
        .toList(growable: false);
    if (incoming.isEmpty) {
      return;
    }
    await _chat.markDelivered(matchId, incoming);
    await _chat.markRead(matchId, incoming);
  }

  Future<void> loadOlder() async {
    if (loadingOlder || !hasMore || messages.isEmpty) {
      return;
    }
    loadingOlder = true;
    notifyListeners();
    final page = await _chat.loadOlder(matchId: matchId, before: messages.first);
    messages.insertAll(0, page.messages);
    hasMore = page.hasMore;
    loadingOlder = false;
    notifyListeners();
  }

  void onComposerChanged(String text) {
    _typingDebounce?.cancel();
    if (!canChat) {
      return;
    }
    _typingDebounce = Timer(ChatPolicy.typingDebounce, () {
      final typing = text.trim().isNotEmpty;
      if (typing == _typingSent) {
        return;
      }
      _typingSent = typing;
      unawaited(_chat.setTyping(matchId: matchId, isTyping: typing));
    });
  }

  Future<Result<void>> send(String text) async {
    if (!canChat) {
      error = ChatStrings.matchInactive;
      notifyListeners();
      return const Err(AuthzFailure(ChatStrings.matchInactive));
    }
    sending = true;
    error = null;
    notifyListeners();
    try {
      await _chat.sendText(
        matchId: matchId,
        receiverId: otherUid,
        text: text,
      );
      _typingSent = false;
      unawaited(_chat.setTyping(matchId: matchId, isTyping: false));
      sending = false;
      notifyListeners();
      return const Success(null);
    } on Object catch (err) {
      sending = false;
      final failure = SocialErrorMapper.map(err);
      error = failure.message;
      notifyListeners();
      return Err(failure);
    }
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    unawaited(_messageSub?.cancel());
    unawaited(_typingSub?.cancel());
    unawaited(_presenceSub?.cancel());
    if (_typingSent) {
      unawaited(_chat.setTyping(matchId: matchId, isTyping: false));
    }
    super.dispose();
  }
}
