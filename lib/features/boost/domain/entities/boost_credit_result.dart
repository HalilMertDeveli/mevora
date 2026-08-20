/// Result of a verified IAP. Credits balance; does not activate visibility.
class BoostCreditResult {
  const BoostCreditResult({
    required this.purchaseId,
    required this.productId,
    required this.boostCount,
    required this.balance,
    this.alreadyProcessed = false,
  });

  final String purchaseId;
  final String productId;
  final int boostCount;
  final int balance;
  final bool alreadyProcessed;
}
