import 'package:mevora/features/boost/domain/entities/boost.dart';

/// Result of a verified IAP. Duration packs activate Boost immediately.
class BoostCreditResult {
  const BoostCreditResult({
    required this.purchaseId,
    required this.productId,
    required this.boostCount,
    required this.balance,
    this.alreadyProcessed = false,
    this.boost,
  });

  final String purchaseId;
  final String productId;
  final int boostCount;
  final int balance;
  final bool alreadyProcessed;
  final Boost? boost;

  bool get didActivate => boost != null;
}
