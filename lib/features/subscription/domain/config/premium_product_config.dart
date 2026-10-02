import 'package:mevora/features/subscription/domain/entities/premium_plan.dart';

/// Which store products count as Premium, and nothing else.
///
/// There is no default product id on purpose. Play Console and App Store
/// Connect own the real identifiers; inventing one here would either query a
/// product that does not exist or, worse, quietly match some other product.
/// With nothing configured the paywall says Premium is unavailable rather than
/// showing a plan nobody can buy — the same fail-closed stance the backend
/// catalogue takes.
class PremiumProductConfig {
  const PremiumProductConfig({this.android = const [], this.ios = const []});

  /// Reads ids from `--dart-define`, matching the backend's
  /// `PREMIUM_ANDROID_PRODUCT_IDS` format: comma separated, each entry either
  /// `productId` or `productId:basePlanId`.
  factory PremiumProductConfig.fromEnvironment() {
    const android = String.fromEnvironment('PREMIUM_ANDROID_PRODUCT_IDS');
    const ios = String.fromEnvironment('PREMIUM_IOS_PRODUCT_IDS');
    return PremiumProductConfig(android: _parse(android), ios: _parse(ios));
  }

  final List<PremiumProductRef> android;
  final List<PremiumProductRef> ios;

  bool get isConfigured => android.isNotEmpty || ios.isNotEmpty;

  List<PremiumProductRef> forPlatform(PremiumPlatform platform) {
    return switch (platform) {
      PremiumPlatform.android => android,
      PremiumPlatform.ios => ios,
    };
  }

  /// Store query keys. Google is asked for the product id; the base plan is a
  /// detail inside it, not a separate queryable product.
  Set<String> queryIdsFor(PremiumPlatform platform) {
    return forPlatform(platform).map((ref) => ref.productId).toSet();
  }

  /// Guards what the client is willing to send as evidence. The backend
  /// re-checks this; agreeing here just avoids a pointless round trip.
  bool allows(PremiumPlatform platform, String productId) {
    return forPlatform(platform).any((ref) => ref.productId == productId);
  }

  /// Whether a plan the store describes is one this build sells. Same rule as
  /// the backend catalogue: an entry with a base plan matches that base plan
  /// only, an entry without one matches every base plan of the product.
  bool allowsPlan(
    PremiumPlatform platform,
    String productId,
    String? basePlanId,
  ) {
    return forPlatform(platform).any(
      (ref) =>
          ref.productId == productId &&
          (ref.basePlanId == null || ref.basePlanId == basePlanId),
    );
  }

  static List<PremiumProductRef> _parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const [];
    }
    final refs = <PremiumProductRef>[];
    for (final entry in trimmed.split(',')) {
      final parts = entry.split(':').map((part) => part.trim()).toList();
      final productId = parts.isEmpty ? '' : parts.first;
      if (productId.isEmpty) {
        continue;
      }
      final basePlanId = parts.length > 1 && parts[1].isNotEmpty
          ? parts[1]
          : null;
      refs.add(PremiumProductRef(productId: productId, basePlanId: basePlanId));
    }
    return List.unmodifiable(refs);
  }
}

/// A configured product, before the store has said anything about it.
class PremiumProductRef {
  const PremiumProductRef({required this.productId, this.basePlanId});

  final String productId;
  final String? basePlanId;
}
