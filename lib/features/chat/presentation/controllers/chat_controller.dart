import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/errors/social_error_mapper.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/chat/debug/chat_debug_log.dart';
import 'package:mevora/features/chat/domain/chat_policy.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/chat/domain/repositories/chat_repository.dart';
import 'package:mevora/features/chat/presentation/chat_strings.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/presence_status.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';
import 'package:mevora/features/matching/domain/services/presence_subtitle.dart';
import 'package:mevora/features/safety/domain/safety_policy.dart';
import 'package:mevora/features/settings/domain/entities/user_settings.dart';
import 'package:mevora/features/settings/domain/repositories/settings_hub_repository.dart';
import 'package:mevora/l10n/app_localizations.dart';

class ChatController extends ChangeNotifier {
  ChatController({
    required this.matchId,
    required ChatRepository chatRepository,
    required MatchRepository matchRepository,
    required SafetyRepository safetyRepository,
    required PresenceRepository presenceRepository,
    required AuthUidSource uidSource,
    SettingsHubRepository? settingsHub,
  }) : _chat = chatRepository,
       _matches = matchRepository,
       _safety = safetyRepository,
       _presence = presenceRepository,
       _uidSource = uidSource,
       _settingsHub = settingsHub;

  final String matchId;
  final ChatRepository _chat;
  final MatchRepository _matches;
  final SafetyRepository _safety;
  final PresenceRepository _presence;
  final AuthUidSource _uidSource;
  final SettingsHubRepository? _settingsHub;

  final List<ChatMessage> messages = [];
  Match? match;
  PresenceStatus presence = PresenceStatus.offline;
  PresenceWatch? presenceWatch;
  UserPrivacy? otherPrivacy;
  UserPrivacy? ownPrivacy;
  String? typingUid;
  String? error;
  bool sending = false;
  bool loadingOlder = false;
  bool hasMore = true;
  bool blocked = false;

  StreamSubscription<List<ChatMessage>>? _messageSub;
  StreamSubscription<Map<String, DateTime>>? _typingSub;
  StreamSubscription<PresenceWatch>? _presenceSub;
  StreamSubscription<UserPrivacy>? _otherPrivacySub;
  StreamSubscription<UserPrivacy>? _ownPrivacySub;
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

  /// Retained read-only conversation whose counterpart deleted their account.
  /// Distinct from an unmatch or block, which keep the existing banner copy.
  bool get isDeletedAccountThread {
    final current = uid;
    final value = match;
    if (current == null || value == null) {
      return false;
    }
    return value.isDeletedAccountHistoryFor(current);
  }

  bool get canCall => canChat;

  String? headerSubtitle(AppLocalizations l10n) {
    return PresenceSubtitle.chatHeader(
      l10n: l10n,
      presence: presenceWatch,
      privacy: otherPrivacy,
      isTyping: typingUid == otherUid && otherUid.isNotEmpty,
    );
  }

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
    if (match != null && otherUid.isNotEmpty) {
      unawaited(_warmE2eeSession(current, otherUid));
    }
    ChatDebugLog.event(
      'chat_started',
      fields: {
        'matchId': matchId,
        'uid': current,
        'otherUid': otherUid,
        'canChat': canChat,
      },
    );
    _messageSub = _chat.watchLatest(matchId).listen((value) {
      messages
        ..clear()
        ..addAll(value);
      if (value.isNotEmpty) {
        ChatDebugLog.messageSnapshot(
          action: 'messages_snapshot',
          matchId: matchId,
          message: value.last,
        );
      }
      unawaited(_acknowledge(value));
      notifyListeners();
    }, onError: (_) {});
    _typingSub = _chat.watchTyping(matchId).listen((value) {
      final other = otherUid;
      final at = value[other];
      final typingAllowed = PresenceSubtitle.showsTyping(otherPrivacy);
      typingUid =
          typingAllowed && ChatPolicy.isTypingFresh(at) ? other : null;
      notifyListeners();
    }, onError: (_) {});
    _presenceSub = _presence.watch(otherUid).listen((value) {
      presenceWatch = value;
      presence = PresenceSubtitle.listBadge(
        presence: value,
        privacy: otherPrivacy,
      );
      notifyListeners();
    }, onError: (_) {});
    final hub = _settingsHub;
    if (hub != null && otherUid.isNotEmpty) {
      _otherPrivacySub = hub.watchPrivacy(otherUid).listen((value) {
        otherPrivacy = value;
        presence = PresenceSubtitle.listBadge(
          presence: presenceWatch,
          privacy: value,
        );
        notifyListeners();
      }, onError: (_) {});
      _ownPrivacySub = hub.watchPrivacy(current).listen((value) {
        ownPrivacy = value;
        notifyListeners();
      }, onError: (_) {});
    }
    notifyListeners();
  }

  Future<void> _warmE2eeSession(String current, String peerUid) async {
    try {
      final active = await _chat.isE2eeActive(
        matchId: matchId,
        peerUid: peerUid,
      );
      ChatDebugLog.event(
        'e2ee_session_warmup',
        fields: {
          'matchId': matchId,
          'uid': current,
          'peerUid': peerUid,
          'active': active,
        },
      );
    } on Object {
      ChatDebugLog.event(
        'e2ee_session_warmup_failed',
        fields: {'matchId': matchId, 'peerUid': peerUid},
      );
    }
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
    if (!canChat || !PresenceSubtitle.showsTyping(ownPrivacy)) {
      if (_typingSent) {
        _typingSent = false;
        unawaited(_chat.setTyping(matchId: matchId, isTyping: false));
      }
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
      final sent = await _chat.sendText(
        matchId: matchId,
        receiverId: otherUid,
        text: text,
      );
      ChatDebugLog.messageSnapshot(
        action: 'message_sent',
        matchId: matchId,
        message: sent,
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
    unawaited(_otherPrivacySub?.cancel());
    unawaited(_ownPrivacySub?.cancel());
    unawaited(_matchSub?.cancel());
    if (_typingSent) {
      unawaited(_chat.setTyping(matchId: matchId, isTyping: false));
    }
    super.dispose();
  }
}
