/// Server-configurable Boost pack. Store prices always win over [fallbackPriceAmount].
class BoostPack {
  const BoostPack({
    required this.productId,
    required this.displayOrder,
    this.boostCount = 0,
    this.fallbackPriceAmount = 0,
    this.fallbackCurrency = 'TRY',
    this.duration = const Duration(days: 7),
    this.active = true,
    this.storefront = true,
    this.featured = false,
    this.title = '',
  });

  final String productId;

  /// Legacy wallet credits. Duration packs use 0.
  final int boostCount;
  final int displayOrder;
  final double fallbackPriceAmount;
  final String fallbackCurrency;
  final Duration duration;
  final bool active;

  /// Shown on the Boost storefront. Legacy SKUs stay verifiable but hidden.
  final bool storefront;
  final bool featured;
  final String title;

  int get durationDays => duration.inDays;

  bool get isDurationPack => duration.inHours >= 24;

  /// Display-only fallback. Never charged; stores set the real price.
  String get fallbackPriceLabel {
    if (fallbackPriceAmount <= 0) {
      return '';
    }
    final fixed = fallbackPriceAmount.toStringAsFixed(2);
    final parts = fixed.split('.');
    if (fallbackCurrency == 'TRY') {
      return '₺${parts[0]},${parts[1]}';
    }
    return '$fallbackCurrency $fixed';
  }
}
