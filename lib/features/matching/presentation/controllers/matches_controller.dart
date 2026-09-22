import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/features/matching/domain/models/presence_status.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';
import 'package:mevora/features/matching/domain/services/presence_subtitle.dart';
import 'package:mevora/features/relationship/domain/config/relationship_question_config.dart';
import 'package:mevora/features/settings/domain/entities/user_settings.dart';
import 'package:mevora/features/settings/domain/repositories/settings_hub_repository.dart';

class MatchesController extends ChangeNotifier {
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
  StreamSubscription<List<MatchListItem>>? _archivedSubscription;
  final Map<String, StreamSubscription<PresenceWatch>> _presenceSubs = {};
  final Map<String, StreamSubscription<UserPrivacy>> _privacySubs = {};
  final Map<String, PresenceWatch> _presenceByUid = {};
  final Map<String, UserPrivacy> _privacyByUid = {};

  List<MatchListItem> items = const [];

  /// Read-only conversations kept after the counterpart deleted their account.
  /// Deliberately separate from [items]: these are not active relationships and
  /// must not feed match counts, ranking, or engagement metrics.
  List<MatchListItem> archivedItems = const [];
  bool loading = true;
  String? error;

  String? get uid => _uidSource.currentUid;

  int get mutualLikeCount =>
      items.where((item) => !item.match.isRelationshipTest).length;

  /// Matches with a recent message — user is actively chatting.
  int get activeConversationCount {
    final current = uid;
    if (current == null) {
      return 0;
    }
    final cutoff = DateTime.now().subtract(
      RelationshipQuestionConfig.activeConversationWindow,
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
    unawaited(_archivedSubscription?.cancel());
    _clearPresenceSubscriptions();
    if (current == null) {
      items = const [];
      archivedItems = const [];
      loading = false;
      notifyListeners();
      return;
    }
    _subscription = _matchRepository.watchMatches(current).listen((value) {
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
    // No presence subscriptions here: a deleted account has no presence, and the
    // history list must never show an online state.
    _archivedSubscription =
        _matchRepository.watchArchivedMatches(current).listen((value) {
      archivedItems = value;
      notifyListeners();
    }, onError: (_) {
      // History is supplementary; a failure here must not break active matches.
      archivedItems = const [];
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
      _presenceSubs.putIfAbsent(otherId, () {
        return _presenceRepository.watch(otherId).listen((watch) {
          _presenceByUid[otherId] = watch;
          notifyListeners();
        }, onError: (_) {});
      });
      final hub = _settingsHub;
      if (hub != null) {
        _privacySubs.putIfAbsent(otherId, () {
          return hub.watchPrivacy(otherId).listen((privacy) {
            _privacyByUid[otherId] = privacy;
            notifyListeners();
          }, onError: (_) {});
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
    unawaited(_archivedSubscription?.cancel());
    _clearPresenceSubscriptions();
    super.dispose();
  }
}

abstract final class MatchingError {
  static const String generic = 'Eşleşmeler yüklenemedi. Lütfen tekrar dene.';
}
