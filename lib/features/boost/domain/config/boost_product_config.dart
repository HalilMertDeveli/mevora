import 'package:mevora/features/boost/domain/config/boost_pack_catalog.dart';

/// Store product identifiers and Boost duration. Prices are never stored here.
///
/// Pack SKUs live in [BoostPackCatalog] / Firestore `boostProducts`. Create them
/// in App Store Connect and Play Console, then override with `--dart-define`
/// if they differ per environment.
class BoostProductConfig {
  const BoostProductConfig({
    this.iosProductId = defaultIosProductId,
    this.androidProductId = defaultAndroidProductId,
    this.duration = defaultDuration,
    this.displayOrder = 0,
  });

  static const String defaultIosProductId = BoostPackCatalog.legacyProductId;
  static const String defaultAndroidProductId = BoostPackCatalog.legacyProductId;
  static const Duration defaultDuration = Duration(minutes: 30);

  /// Legacy single-SKU placeholder. Still accepted as a 1-Boost pack.
  final String iosProductId;

  /// Legacy single-SKU placeholder. Still accepted as a 1-Boost pack.
  final String androidProductId;

  /// How long an activated Boost lasts. Server uses the same value.
  final Duration duration;

  /// Sort key kept for compatibility with the original single product.
  final int displayOrder;

  /// Reads IDs from dart-define without baking store prices into the binary.
  factory BoostProductConfig.fromEnvironment() {
    const ios = String.fromEnvironment(
      'BOOST_IOS_PRODUCT_ID',
      defaultValue: defaultIosProductId,
    );
    const android = String.fromEnvironment(
      'BOOST_ANDROID_PRODUCT_ID',
      defaultValue: defaultAndroidProductId,
    );
    const minutes = int.fromEnvironment(
      'BOOST_DURATION_MINUTES',
      defaultValue: 30,
    );
    const order = int.fromEnvironment('BOOST_DISPLAY_ORDER', defaultValue: 0);
    return const BoostProductConfig(
      iosProductId: ios,
      androidProductId: android,
      duration: Duration(minutes: minutes < 1 ? 30 : minutes),
      displayOrder: order,
    );
  }

  String productIdFor(PurchasePlatform platform) {
    return switch (platform) {
      PurchasePlatform.ios => iosProductId,
      PurchasePlatform.android => androidProductId,
    };
  }

  bool isAllowedProductId(String productId, [PurchasePlatform? platform]) {
    if (BoostPackCatalog.isAllowed(productId)) {
      return true;
    }
    if (platform == null) {
      return productId == iosProductId || productId == androidProductId;
    }
    return productId == productIdFor(platform);
  }

  Set<String> get allProductIds => {
    iosProductId,
    androidProductId,
    ...BoostPackCatalog.skus,
  };
}

enum PurchasePlatform { ios, android }
