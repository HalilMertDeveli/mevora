/// Which store a purchase came from. Mirrors the `platform` the backend
/// verifier expects.
enum PremiumPlatform { android, ios }

enum PremiumPlanPeriod { monthly, yearly, unknown }

/// A Premium plan as the store describes it.
///
/// The price is whatever the store returned, already localised for the store
/// account. Mevora never formats or invents a price: a hardcoded "₺199" would
/// be wrong for every other market, wrong after any price change, and wrong
/// for anyone on an introductory offer.
class PremiumPlan {
  const PremiumPlan({
    required this.productId,
    required this.title,
    required this.description,
    required this.formattedPrice,
    this.basePlanId,
    this.period = PremiumPlanPeriod.unknown,
  });

  final String productId;

  /// Google base plan, when the store models one. Null on Apple.
  final String? basePlanId;

  final String title;
  final String description;

  /// Store-formatted, localised price — display verbatim.
  final String formattedPrice;

  final PremiumPlanPeriod period;

  /// Stable identity for selection. Google can put monthly and yearly under
  /// one product id, so the base plan has to be part of the key.
  String get planKey =>
      basePlanId == null ? productId : '$productId:$basePlanId';
}

/// Evidence handed to the backend. Deliberately carries no entitlement claim —
/// not `isPremium`, not an expiry, not a status. The server reads those from
/// the store itself.
class PremiumPurchaseEvidence {
  const PremiumPurchaseEvidence({
    required this.platform,
    required this.purchaseToken,
    this.productId,
  });

  final PremiumPlatform platform;

  /// Play purchase token, or the Apple transaction/receipt evidence.
  final String purchaseToken;

  /// Only so the client can drop obviously-unrelated purchases (a Boost pack)
  /// before calling. The backend ignores it and trusts the store.
  final String? productId;
}
