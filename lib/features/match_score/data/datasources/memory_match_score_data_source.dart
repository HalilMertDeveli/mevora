import 'dart:async';

import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/features/match_score/data/datasources/match_score_data_source.dart';
import 'package:mevora/features/match_score/domain/entities/match_score.dart';
import 'package:mevora/features/match_score/domain/services/match_feedback_filter.dart';
import 'package:mevora/features/match_score/domain/services/match_score_policy.dart';

class _MatchFlags {
  bool matchBonusAwarded = false;
  bool interactionBonusAwarded = false;
  DateTime? matchedAt;
  List<String> userIds = const [];
  final Set<String> messagedUserIds = {};
  bool isActive = true;
  String? unmatchedBy;
  String? endedReason;
}

/// In-memory stand-in for Cloud Functions match-score rules.
class MemoryMatchScoreDataSource implements MatchScoreDataSource {
  MemoryMatchScoreDataSource({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<String, int> _scores = {};
  final Map<String, int> _matchCounts = {};
  final Map<String, List<MatchScoreHistoryEntry>> _history = {};
  final Map<String, _MatchFlags> _matches = {};
  final Map<String, Map<String, PendingMatchFeedback>> _pending = {};
  final Map<String, Map<String, MatchFeedbackRecord>> _feedback = {};
  final _scoreControllers = <String, StreamController<MatchScoreSnapshot>>{};
  final _historyControllers =
      <String, StreamController<List<MatchScoreHistoryEntry>>>{};
  final _pendingControllers =
      <String, StreamController<List<PendingMatchFeedback>>>{};
  int _historySeq = 0;

  int scoreOf(String uid) =>
      MatchScorePolicy.seed(_scores.containsKey(uid) ? _scores[uid] : null);

  List<MatchScoreHistoryEntry> historyOf(String uid) =>
      List.unmodifiable(_history[uid] ?? const []);

  MatchFeedbackRecord? feedbackOf(String uid, String matchId) =>
      _feedback[uid]?[matchId];

  void ensureUser(String uid) {
    if (_scores.containsKey(uid)) {
      return;
    }
    _scores[uid] = MatchScorePolicy.initialScore;
    _matchCounts[uid] = 0;
    _emitScore(uid);
  }

  void recordMatchCreated({
    required String matchId,
    required List<String> userIds,
    required DateTime matchedAt,
  }) {
    final flags = _matches.putIfAbsent(matchId, _MatchFlags.new);
    flags.userIds = List<String>.from(userIds);
    flags.matchedAt = matchedAt;
    flags.isActive = true;
    flags.unmatchedBy = null;
    flags.endedReason = null;
    if (!flags.interactionBonusAwarded) {
      flags.messagedUserIds.clear();
    }
    if (!MatchScorePolicy.shouldAwardMatchBonus(
      alreadyAwarded: flags.matchBonusAwarded,
    )) {
      return;
    }
    flags.matchBonusAwarded = true;
    for (final uid in userIds) {
      ensureUser(uid);
      _scores[uid] = scoreOf(uid) + MatchScorePolicy.matchBonus;
      _matchCounts[uid] = (_matchCounts[uid] ?? 0) + 1;
      _appendHistory(uid, MatchScoreHistoryType.newMatch);
      _emitScore(uid);
    }
  }

  void recordMessage({
    required String matchId,
    required String senderId,
    required DateTime now,
  }) {
    final flags = _matches[matchId];
    if (flags == null || !flags.isActive) {
      return;
    }
    flags.messagedUserIds.add(senderId);
    final matchedAt = flags.matchedAt ?? now;
    if (!MatchScorePolicy.shouldAwardInteractionBonus(
      alreadyAwarded: flags.interactionBonusAwarded,
      matchedAt: matchedAt,
      now: now,
      messagedUserIds: flags.messagedUserIds,
      userIds: flags.userIds,
    )) {
      return;
    }
    flags.interactionBonusAwarded = true;
    for (final uid in flags.userIds) {
      ensureUser(uid);
      _scores[uid] = scoreOf(uid) + MatchScorePolicy.interactionBonus;
      _appendHistory(uid, MatchScoreHistoryType.postMatchInteraction);
      _emitScore(uid);
    }
  }

  void recordMatchEnded({
    required String matchId,
    required String endedBy,
    required String reason,
    required List<String> userIds,
  }) {
    final flags = _matches.putIfAbsent(matchId, _MatchFlags.new);
    flags.userIds = List<String>.from(userIds);
    flags.isActive = false;
    flags.unmatchedBy = endedBy;
    flags.endedReason = reason;
    final other = userIds.where((id) => id != endedBy).firstOrNull;
    if (other == null) {
      return;
    }
    if (_feedback[other]?[matchId] != null) {
      return;
    }
    final pending = PendingMatchFeedback(
      matchId: matchId,
      endedBy: endedBy,
      endedReason: reason,
      createdAt: _clock(),
    );
    _pending.putIfAbsent(other, () => {})[matchId] = pending;
    _emitPending(other);
  }

  @override
  Stream<MatchScoreSnapshot> watchScore(String uid) {
    final controller = _scoreControllers.putIfAbsent(
      uid,
      () => StreamController<MatchScoreSnapshot>.broadcast(),
    );
    scheduleMicrotask(() => _emitScore(uid));
    return controller.stream;
  }

  @override
  Future<MatchScoreSnapshot> getScore(String uid) async {
    ensureUser(uid);
    return _snapshot(uid);
  }

  @override
  Stream<List<MatchScoreHistoryEntry>> watchHistory(String uid) {
    final controller = _historyControllers.putIfAbsent(
      uid,
      () => StreamController<List<MatchScoreHistoryEntry>>.broadcast(),
    );
    scheduleMicrotask(() => _emitHistory(uid));
    return controller.stream;
  }

  @override
  Stream<List<PendingMatchFeedback>> watchPendingFeedback(String uid) {
    final controller = _pendingControllers.putIfAbsent(
      uid,
      () => StreamController<List<PendingMatchFeedback>>.broadcast(),
    );
    scheduleMicrotask(() => _emitPending(uid));
    return controller.stream;
  }

  @override
  Future<void> submitFeedback({
    required String uid,
    required String matchId,
    required String text,
  }) async {
    final flags = _matches[matchId];
    final already = _feedback[uid]?[matchId] != null;
    if (flags == null ||
        !MatchScorePolicy.canSubmitFeedback(
          uid: uid,
          isActive: flags.isActive,
          unmatchedBy: flags.unmatchedBy,
          alreadySubmitted: already,
        )) {
      throw const AuthzException('not-eligible', code: 'failed-precondition');
    }
    final cleaned = MatchFeedbackFilter.sanitize(text);
    if (cleaned.isEmpty) {
      throw const ValidationException('empty');
    }
    _feedback.putIfAbsent(uid, () => {})[matchId] = MatchFeedbackRecord(
      matchId: matchId,
      text: cleaned,
      endedBy: flags.unmatchedBy,
      endedReason: flags.endedReason,
      createdAt: _clock(),
    );
    _pending[uid]?.remove(matchId);
    _emitPending(uid);
  }

  @override
  Future<void> dismissFeedback({
    required String uid,
    required String matchId,
  }) async {
    _pending[uid]?.remove(matchId);
    _emitPending(uid);
  }

  MatchScoreSnapshot _snapshot(String uid) {
    return MatchScoreSnapshot(
      score: scoreOf(uid),
      matchCount: _matchCounts[uid] ?? 0,
    );
  }

  void _appendHistory(String uid, MatchScoreHistoryType type) {
    _historySeq += 1;
    final entry = MatchScoreHistoryEntry(
      id: 'h$_historySeq',
      type: type,
      delta: 1,
      createdAt: _clock(),
    );
    _history.putIfAbsent(uid, () => []).insert(0, entry);
    _emitHistory(uid);
  }

  void _emitScore(String uid) {
    _scoreControllers[uid]?.add(_snapshot(uid));
  }

  void _emitHistory(String uid) {
    _historyControllers[uid]?.add(historyOf(uid));
  }

  void _emitPending(String uid) {
    final items = _pending[uid]?.values.toList(growable: false) ?? const [];
    _pendingControllers[uid]?.add(items);
  }
}
