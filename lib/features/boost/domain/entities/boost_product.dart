/// Store-backed Boost SKU. [localizedPrice] and [currency] come from
/// StoreKit / Play Billing when available. [fallbackPrice] is display-only.
class BoostProduct {
  const BoostProduct({
    required this.productId,
    required this.title,
    required this.description,
    required this.localizedPrice,
    required this.currency,
    required this.available,
    required this.duration,
    this.displayOrder = 0,
    this.boostCount = 0,
    this.featured = false,
    this.fallbackPrice,
  });

  final String productId;
  final String title;
  final String description;

  /// Store-localized price string, e.g. "₺49,99". Never a client-authored charge.
  final String localizedPrice;

  /// ISO currency from the store, e.g. "TRY".
  final String currency;

  final bool available;
  final Duration duration;
  final int displayOrder;
  final int boostCount;
  final bool featured;

  /// Catalog fallback shown only when the store has not returned a price.
  final String? fallbackPrice;

  int get durationDays => duration.inDays;

  String get displayPrice =>
      localizedPrice.isNotEmpty ? localizedPrice : (fallbackPrice ?? '');
}
