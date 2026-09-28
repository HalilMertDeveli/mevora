enum MatchScoreHistoryType { newMatch, postMatchInteraction }

class MatchScoreSnapshot {
  const MatchScoreSnapshot({
    required this.score,
    this.matchCount = 0,
  });

  final int score;
  final int matchCount;
}

class MatchScoreHistoryEntry {
  const MatchScoreHistoryEntry({
    required this.id,
    required this.type,
    required this.delta,
    required this.createdAt,
  });

  final String id;
  final MatchScoreHistoryType type;
  final int delta;
  final DateTime createdAt;
}

class PendingMatchFeedback {
  const PendingMatchFeedback({
    required this.matchId,
    required this.endedBy,
    required this.endedReason,
    this.createdAt,
  });

  final String matchId;
  final String endedBy;
  final String endedReason;
  final DateTime? createdAt;
}

class MatchFeedbackRecord {
  const MatchFeedbackRecord({
    required this.matchId,
    required this.text,
    this.endedBy,
    this.endedReason,
    this.createdAt,
  });

  final String matchId;
  final String text;
  final String? endedBy;
  final String? endedReason;
  final DateTime? createdAt;
}
