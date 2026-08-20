/// Server-configurable Boost pack. Store prices always win over [fallbackPriceAmount].
class BoostPack {
  const BoostPack({
    required this.productId,
    required this.boostCount,
    required this.displayOrder,
    required this.fallbackPriceAmount,
    this.fallbackCurrency = 'TRY',
    this.duration = const Duration(minutes: 30),
    this.active = true,
    this.title = '',
  });

  final String productId;
  final int boostCount;
  final int displayOrder;
  final double fallbackPriceAmount;
  final String fallbackCurrency;
  final Duration duration;
  final bool active;
  final String title;

  /// Display-only fallback, e.g. "₺49,99". Never charged; stores set the real price.
  String get fallbackPriceLabel {
    final fixed = fallbackPriceAmount.toStringAsFixed(2);
    final parts = fixed.split('.');
    if (fallbackCurrency == 'TRY') {
      return '₺${parts[0]},${parts[1]}';
    }
    return '$fallbackCurrency $fixed';
  }
}
