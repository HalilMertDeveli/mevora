/// Store product identifiers and Boost duration. Prices are never stored here.
///
/// Replace the placeholder IDs in App Store Connect and Play Console, then
/// override with `--dart-define` if they differ per environment.
class BoostProductConfig {
  const BoostProductConfig({
    this.iosProductId = defaultIosProductId,
    this.androidProductId = defaultAndroidProductId,
    this.duration = defaultDuration,
    this.displayOrder = 0,
  });

  static const String defaultIosProductId = 'com.mevora.app.boost';
  static const String defaultAndroidProductId = 'com.mevora.app.boost';
  static const Duration defaultDuration = Duration(minutes: 30);

  /// Placeholder App Store product id. Create this as a Consumable in App Store Connect.
  final String iosProductId;

  /// Placeholder Play Billing product id. Create this as an in-app product (consumable).
  final String androidProductId;

  /// How long an activated Boost lasts. Server uses the same value.
  final Duration duration;

  /// Sort key if more Boost SKUs are added later. MVP has one product.
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

  bool isAllowedProductId(String productId, PurchasePlatform platform) {
    return productId == productIdFor(platform);
  }

  Set<String> get allProductIds => {iosProductId, androidProductId};
}

enum PurchasePlatform { ios, android }
