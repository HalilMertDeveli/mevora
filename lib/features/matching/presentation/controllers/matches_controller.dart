import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';

class MatchesController extends ChangeNotifier {
  MatchesController({
    required MatchRepository matchRepository,
    required AuthUidSource uidSource,
  }) : _matchRepository = matchRepository,
       _uidSource = uidSource;

  final MatchRepository _matchRepository;
  final AuthUidSource _uidSource;
  StreamSubscription<List<MatchListItem>>? _subscription;

  List<MatchListItem> items = const [];
  bool loading = true;
  String? error;

  String? get uid => _uidSource.currentUid;

  int get totalUnread {
    final current = uid;
    if (current == null) {
      return 0;
    }
    return items.fold<int>(0, (sum, item) => sum + item.unreadCount(current));
  }

  void start() {
    final current = uid;
    _subscription?.cancel();
    if (current == null) {
      items = const [];
      loading = false;
      notifyListeners();
      return;
    }
    _subscription = _matchRepository.watchMatches(current).listen((value) {
      items = value;
      loading = false;
      error = null;
      notifyListeners();
    }, onError: (_) {
      error = MatchingError.generic;
      loading = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

abstract final class MatchingError {
  static const String generic = 'Eşleşmeler yüklenemedi. Lütfen tekrar dene.';
}
