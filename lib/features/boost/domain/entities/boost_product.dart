/// Store-backed Boost SKU. [localizedPrice] and [currency] always come from
/// StoreKit / Play Billing — never from Flutter or our backend.
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
  });

  final String productId;
  final String title;
  final String description;

  /// Store-localized price string, e.g. "₺29,99". Never a client-authored value.
  final String localizedPrice;

  /// ISO currency from the store, e.g. "TRY".
  final String currency;

  final bool available;
  final Duration duration;
  final int displayOrder;
}
