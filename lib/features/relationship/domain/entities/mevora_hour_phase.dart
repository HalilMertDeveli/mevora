/// Product phases for the hourly Mevora Hour compatibility event.
enum MevoraHourPhase {
  /// Not showing Mevora Hour chrome (e.g. initial test / idle).
  none,

  /// Next Istanbul hour has not started yet (or user dismissed LIVE).
  upcoming,

  /// Current hour round is OPEN/COLLECTING — join CTA.
  live,

  /// User joined and is answering (or just joined).
  joined,

  /// Answers submitted; waiting for round match.
  answered,

  /// Round result ready for this user.
  result,

  /// This hour's event finished; tease the next hour.
  ended,
}
