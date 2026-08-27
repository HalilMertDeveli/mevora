class MatchingGameRoundInfo {
  const MatchingGameRoundInfo({
    required this.roundId,
    required this.status,
    required this.timezone,
    required this.serverNowMs,
    required this.nextRoundAtMs,
    required this.closesAtMs,
  });

  final String roundId;
  final String status;
  final String timezone;
  final int serverNowMs;
  final int nextRoundAtMs;
  final int closesAtMs;

  bool get isOpen => status == 'OPEN' || status == 'COLLECTING';

  bool get isCompleted => status == 'COMPLETED' || status == 'MATCHING';

  Duration get timeUntilClose {
    final remain = closesAtMs - serverNowMs;
    if (remain <= 0) {
      return Duration.zero;
    }
    return Duration(milliseconds: remain);
  }

  /// Time until the next Istanbul hour boundary (same as close while LIVE).
  Duration get timeUntilNextRound {
    final remain = nextRoundAtMs - serverNowMs;
    if (remain <= 0) {
      return Duration.zero;
    }
    return Duration(milliseconds: remain);
  }

  /// Hour digits from round id `YYYYMMDDHH` (Istanbul wall clock).
  String? get displayHour {
    if (roundId.length < 10) {
      return null;
    }
    return roundId.substring(roundId.length - 2);
  }

  /// Next hour label from [nextRoundAtMs] is not derivable without TZ math;
  /// clients format [displayHour] + 1 mod 24 when teasing the following event.
  String get nextDisplayHour {
    final current = int.tryParse(displayHour ?? '');
    if (current == null) {
      return '--';
    }
    return ((current + 1) % 24).toString().padLeft(2, '0');
  }
}

class MatchingGameResultInfo {
  const MatchingGameResultInfo({
    required this.roundId,
    required this.roundStatus,
    this.participantStatus,
    this.matchId,
    this.compatibilityScore,
    this.partnerUid,
    this.partnerName,
    this.partnerPhotoUrl,
  });

  final String roundId;
  final String roundStatus;
  final String? participantStatus;
  final String? matchId;
  final int? compatibilityScore;
  final String? partnerUid;
  final String? partnerName;
  final String? partnerPhotoUrl;

  bool get isMatched =>
      participantStatus == 'matched' &&
      partnerUid != null &&
      partnerUid!.isNotEmpty;

  bool get isUnmatched => participantStatus == 'unmatched';

  bool get isWaiting =>
      participantStatus == 'submitted' && roundStatus != 'COMPLETED';
}
