import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/features/matching/domain/models/presence_status.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';
import 'package:mevora/features/matching/domain/services/presence_subtitle.dart';
import 'package:mevora/features/settings/domain/entities/user_settings.dart';
import 'package:mevora/features/settings/domain/repositories/settings_hub_repository.dart';

class MatchesController extends ChangeNotifier {
  /// A message within this window counts as an active conversation.
  static const Duration activeConversationWindow = Duration(minutes: 30);

  /// Conversations kept live at once. Scrolling past them widens the window
  /// by another page, so an inbox never listens to every match it has.
  static const int pageSize = 30;

  MatchesController({
    required MatchRepository matchRepository,
    required PresenceRepository presenceRepository,
    required AuthUidSource uidSource,
    SettingsHubRepository? settingsHub,
  }) : _matchRepository = matchRepository,
       _presenceRepository = presenceRepository,
       _uidSource = uidSource,
       _settingsHub = settingsHub;

  final MatchRepository _matchRepository;
  final PresenceRepository _presenceRepository;
  final AuthUidSource _uidSource;
  SettingsHubRepository? _settingsHub;
  StreamSubscription<List<MatchListItem>>? _subscription;
  final Map<String, StreamSubscription<PresenceWatch>> _presenceSubs = {};
  final Map<String, StreamSubscription<UserPrivacy>> _privacySubs = {};
  final Map<String, PresenceWatch> _presenceByUid = {};
  final Map<String, UserPrivacy> _privacyByUid = {};

  List<MatchListItem> items = const [];
  bool loading = true;
  String? error;
  int _limit = pageSize;
  String? _listeningUid;

  String? get uid => _uidSource.currentUid;

  /// The live window is full, so older conversations may exist beyond it.
  bool get hasMore => items.length >= _limit;

  int get mutualLikeCount =>
      items.where((item) => !item.match.isRelationshipTest).length;

  /// Matches with a recent message — user is actively chatting.
  int get activeConversationCount {
    final current = uid;
    if (current == null) {
      return 0;
    }
    final cutoff = DateTime.now().subtract(
      activeConversationWindow,
    );
    return items.where((item) {
      final match = item.match;
      if (!match.isActive) {
        return false;
      }
      final last = match.lastMessageAt;
      if (last == null) {
        return false;
      }
      return last.isAfter(cutoff);
    }).length;
  }

  int get totalUnread {
    final current = uid;
    if (current == null) {
      return 0;
    }
    return items.fold<int>(0, (sum, item) => sum + item.unreadCount(current));
  }

  void attachSettingsHub(SettingsHubRepository? settingsHub) {
    if (identical(settingsHub, _settingsHub)) {
      return;
    }
    _settingsHub = settingsHub;
    if (items.isNotEmpty) {
      _syncPresenceSubscriptions(items);
    }
  }

  void start() {
    final current = uid;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _clearPresenceSubscriptions();
    _limit = pageSize;
    _listeningUid = current;
    if (current == null) {
      items = const [];
      loading = false;
      notifyListeners();
      return;
    }
    _listen(current);
  }

  /// App came back to the foreground. Healthy listeners keep running — the
  /// SDK reconnects them and replays only what changed — so this restarts
  /// just the ones that failed, instead of re-reading the whole inbox and
  /// every partner's presence on each resume.
  void resume() {
    final current = uid;
    if (current != _listeningUid || _subscription == null || error != null) {
      start();
      return;
    }
    _syncPresenceSubscriptions(items);
  }

  /// Widens the live window by one page. The query is replaced, not
  /// stacked, so the inbox stays one listener however far it scrolls.
  void loadMore() {
    final current = uid;
    if (current == null || loading || !hasMore) {
      return;
    }
    _limit += pageSize;
    unawaited(_subscription?.cancel());
    _listen(current);
  }

  void _listen(String current) {
    _subscription = _matchRepository
        .watchMatches(current, limit: _limit)
        .listen((value) {
          items = value;
          loading = false;
          error = null;
          _syncPresenceSubscriptions(value);
          notifyListeners();
        }, onError: (_) {
          error = MatchingError.generic;
          loading = false;
          notifyListeners();
        });
  }

  PresenceStatus presenceFor(String otherUserId) {
    return PresenceSubtitle.listBadge(
      presence: _presenceByUid[otherUserId],
      privacy: _privacyByUid[otherUserId],
    );
  }

  void _syncPresenceSubscriptions(List<MatchListItem> value) {
    final otherIds = value.map((item) => item.otherUserId).toSet();
    for (final otherId in otherIds) {
      // A failed listener is dropped so the next sync (a new snapshot or a
      // resume) opens it again; healthy ones are never reopened.
      _presenceSubs.putIfAbsent(otherId, () {
        late final StreamSubscription<PresenceWatch> sub;
        sub = _presenceRepository.watch(otherId).listen((watch) {
          _presenceByUid[otherId] = watch;
          notifyListeners();
        }, onError: (_) {
          if (identical(_presenceSubs[otherId], sub)) {
            _presenceSubs.remove(otherId);
          }
          unawaited(sub.cancel());
        });
        return sub;
      });
      final hub = _settingsHub;
      if (hub != null) {
        _privacySubs.putIfAbsent(otherId, () {
          late final StreamSubscription<UserPrivacy> sub;
          sub = hub.watchPrivacy(otherId).listen((privacy) {
            _privacyByUid[otherId] = privacy;
            notifyListeners();
          }, onError: (_) {
            if (identical(_privacySubs[otherId], sub)) {
              _privacySubs.remove(otherId);
            }
            unawaited(sub.cancel());
          });
          return sub;
        });
      }
    }
    for (final id in _presenceSubs.keys.toList(growable: false)) {
      if (!otherIds.contains(id)) {
        unawaited(_presenceSubs.remove(id)?.cancel());
        _presenceByUid.remove(id);
      }
    }
    for (final id in _privacySubs.keys.toList(growable: false)) {
      if (!otherIds.contains(id)) {
        unawaited(_privacySubs.remove(id)?.cancel());
        _privacyByUid.remove(id);
      }
    }
  }

  void _clearPresenceSubscriptions() {
    for (final sub in _presenceSubs.values) {
      unawaited(sub.cancel());
    }
    for (final sub in _privacySubs.values) {
      unawaited(sub.cancel());
    }
    _presenceSubs.clear();
    _privacySubs.clear();
    _presenceByUid.clear();
    _privacyByUid.clear();
  }

  @override
  void notifyListeners() {
    if (_closed) {
      return;
    }
    super.notifyListeners();
  }

  bool _closed = false;

  @override
  void dispose() {
    _closed = true;
    unawaited(_subscription?.cancel());
    _clearPresenceSubscriptions();
    super.dispose();
  }
}

abstract final class MatchingError {
  static const String generic = 'Eşleşmeler yüklenemedi. Lütfen tekrar dene.';
}
