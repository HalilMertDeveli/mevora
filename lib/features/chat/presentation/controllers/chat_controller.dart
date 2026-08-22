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
  StreamSubscription<Match?>? _matchSub;
  Timer? _typingDebounce;
  Timer? _typingIdle;
  bool _typingSent = false;
  double? uploadProgress;
  bool recording = false;

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
    try {
      match = await _matches.getMatch(matchId);
    } on Object {
      match = null;
    }
    try {
      _matchSub = _matches.watchMatch(matchId).listen((value) {
        if (value != null) {
          match = value;
          notifyListeners();
        }
      }, onError: (_) {});
    } on Object {
      // Some adapters only expose getMatch.
    }
    try {
      if (match != null) {
        blocked = await _safety.isBlockedPair(current, otherUid);
      }
    } on Object {
      blocked = false;
    }
    try {
      await _matches.markOpened(matchId, current);
    } on Object {
      // Demo matches and offline clients still open the thread.
    }
    _messageSub = _chat.watchLatest(matchId).listen((value) {
      messages
        ..clear()
        ..addAll(value);
      unawaited(_acknowledge(value));
      notifyListeners();
    }, onError: (_) {});
    _typingSub = _chat.watchTyping(matchId).listen((value) {
      final other = otherUid;
      final at = value[other];
      typingUid = ChatPolicy.isTypingFresh(at) ? other : null;
      notifyListeners();
    }, onError: (_) {});
    _presenceSub = _presence.watch(otherUid).listen((value) {
      presence = PresenceStatusX.fromUpdatedAt(
        updatedAt: value.updatedAt,
        hideOnlineStatus: value.hideOnlineStatus,
      );
      notifyListeners();
    }, onError: (_) {});
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
    _typingIdle?.cancel();
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
    if (text.trim().isNotEmpty) {
      _typingIdle = Timer(ChatPolicy.typingTtl, () {
        if (!_typingSent) {
          return;
        }
        _typingSent = false;
        unawaited(_chat.setTyping(matchId: matchId, isTyping: false));
      });
    }
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

  Future<Result<void>> sendImage(ChatMediaBytes media) {
    return _sendMedia(
      () => _chat.sendImage(
        matchId: matchId,
        receiverId: otherUid,
        media: media,
        onProgress: _onUploadProgress,
      ),
    );
  }

  Future<Result<void>> sendVoice(ChatMediaBytes media) {
    return _sendMedia(
      () => _chat.sendVoice(
        matchId: matchId,
        receiverId: otherUid,
        media: media,
        onProgress: _onUploadProgress,
      ),
    );
  }

  void _onUploadProgress(double value) {
    uploadProgress = value;
    notifyListeners();
  }

  Future<Result<void>> _sendMedia(Future<ChatMessage> Function() send) async {
    if (!canChat) {
      error = ChatStrings.matchInactive;
      notifyListeners();
      return const Err(AuthzFailure(ChatStrings.matchInactive));
    }
    sending = true;
    error = null;
    uploadProgress = 0;
    notifyListeners();
    try {
      await send();
      sending = false;
      uploadProgress = null;
      notifyListeners();
      return const Success(null);
    } on Object catch (err) {
      sending = false;
      uploadProgress = null;
      final failure = SocialErrorMapper.map(err);
      error = failure.message;
      notifyListeners();
      return Err(failure);
    }
  }

  Future<Result<void>> deleteOwn(ChatMessage message) async {
    final current = uid;
    if (current == null ||
        !ChatPolicy.canDeleteOwnMessage(message: message, uid: current)) {
      return const Err(AuthzFailure(ChatStrings.notAllowed));
    }
    try {
      await _chat.deleteMessage(matchId: matchId, messageId: message.id);
      return const Success(null);
    } on Object catch (err) {
      final failure = SocialErrorMapper.map(err);
      error = failure.message;
      notifyListeners();
      return Err(failure);
    }
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _typingIdle?.cancel();
    unawaited(_messageSub?.cancel());
    unawaited(_typingSub?.cancel());
    unawaited(_presenceSub?.cancel());
    unawaited(_matchSub?.cancel());
    if (_typingSent) {
      unawaited(_chat.setTyping(matchId: matchId, isTyping: false));
    }
    super.dispose();
  }
}
