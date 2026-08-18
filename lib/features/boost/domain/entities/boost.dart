enum BoostStatus { pending, active, expired, cancelled }

/// Owner-only visibility bonus. Other users never receive this document.
class Boost {
  const Boost({
    required this.boostId,
    required this.userId,
    required this.productId,
    required this.purchaseId,
    required this.status,
    required this.createdAt,
    this.startedAt,
    this.expiresAt,
  });

  final String boostId;
  final String userId;
  final String productId;
  final String purchaseId;
  final BoostStatus status;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? expiresAt;

  bool isActiveAt(DateTime now) {
    if (status != BoostStatus.active) {
      return false;
    }
    if (expiresAt == null) {
      return false;
    }
    // Server time is authoritative. A lagged expire job must not keep Boost live.
    return expiresAt!.isAfter(now);
  }

  Duration remaining(DateTime now) {
    final end = expiresAt;
    if (end == null || !end.isAfter(now)) {
      return Duration.zero;
    }
    return end.difference(now);
  }
}
