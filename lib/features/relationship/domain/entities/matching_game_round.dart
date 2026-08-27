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

  Duration get timeUntilClose {
    final remain = closesAtMs - serverNowMs;
    if (remain <= 0) {
      return Duration.zero;
    }
    return Duration(milliseconds: remain);
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
