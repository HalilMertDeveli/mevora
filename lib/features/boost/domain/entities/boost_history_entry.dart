enum BoostHistoryType { purchase, activation }

/// Owner-only ledger row. Built from `purchases` + `users/{uid}/boosts`.
class BoostHistoryEntry {
  const BoostHistoryEntry({
    required this.id,
    required this.type,
    required this.productId,
    required this.createdAt,
    this.boostCount = 1,
    this.status,
    this.expiresAt,
  });

  final String id;
  final BoostHistoryType type;
  final String productId;
  final int boostCount;
  final DateTime createdAt;
  final String? status;
  final DateTime? expiresAt;
}
