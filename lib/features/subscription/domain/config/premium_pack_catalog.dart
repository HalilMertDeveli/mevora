/// Premium duration packs (one-time store products that grant isPremium + expiresAt).
/// Not auto-renewing subscriptions — store verification writes Firestore entitlement.
class PremiumPackCatalog {
  const PremiumPackCatalog();

  static const String month = 'mevora_premium_1_month';
  static const String year = 'mevora_premium_1_year';

  static const List<String> productIds = [month, year];

  static int durationDaysFor(String productId) {
    switch (productId) {
      case year:
        return 365;
      case month:
      default:
        return 30;
    }
  }
}
