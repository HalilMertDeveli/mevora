import 'package:mevora/features/boost/domain/entities/boost_pack.dart';

/// Offline / default Boost packs. Firestore `boostProducts` is the live source
/// of truth; this catalog is used when the backend is unreachable.
abstract final class BoostPackCatalog {
  static const String legacyProductId = 'com.mevora.app.boost';
  static const String pack1 = 'com.mevora.app.boost.1';
  static const String pack5 = 'com.mevora.app.boost.5';
  static const String pack10 = 'com.mevora.app.boost.10';

  static const List<BoostPack> defaults = [
    BoostPack(
      productId: pack1,
      boostCount: 1,
      displayOrder: 0,
      fallbackPriceAmount: 49.99,
      title: '1 Boost',
    ),
    BoostPack(
      productId: pack5,
      boostCount: 5,
      displayOrder: 1,
      fallbackPriceAmount: 199.99,
      title: '5 Boost',
    ),
    BoostPack(
      productId: pack10,
      boostCount: 10,
      displayOrder: 2,
      fallbackPriceAmount: 349.99,
      title: '10 Boost',
    ),
    BoostPack(
      productId: legacyProductId,
      boostCount: 1,
      displayOrder: 99,
      fallbackPriceAmount: 49.99,
      title: '1 Boost',
    ),
  ];

  static const Set<String> skus = {legacyProductId, pack1, pack5, pack10};

  static List<BoostPack> get storefrontPacks => defaults
      .where((pack) => pack.productId != legacyProductId && pack.active)
      .toList()
    ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

  static BoostPack? packFor(String productId, {List<BoostPack>? catalog}) {
    final source = catalog ?? defaults;
    for (final pack in source) {
      if (pack.productId == productId && pack.active && pack.boostCount > 0) {
        return pack;
      }
    }
    return null;
  }

  static bool isAllowed(String productId, {List<BoostPack>? catalog}) {
    return packFor(productId, catalog: catalog) != null;
  }

  static int boostCountFor(String productId, {List<BoostPack>? catalog}) {
    return packFor(productId, catalog: catalog)?.boostCount ?? 0;
  }

  /// Parses a Remote Config / Firestore JSON array. Invalid rows are skipped.
  static List<BoostPack> parse(Object? raw) {
    if (raw is! List) {
      return List<BoostPack>.from(storefrontPacks);
    }
    final parsed = <BoostPack>[];
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      final data = Map<Object?, Object?>.from(item);
      final productId = data['productId']?.toString() ?? data['sku']?.toString();
      final boostCount = _intOf(data['boostCount'] ?? data['count']);
      if (productId == null || productId.isEmpty || boostCount < 1) {
        continue;
      }
      parsed.add(
        BoostPack(
          productId: productId,
          boostCount: boostCount,
          displayOrder: _intOf(data['displayOrder'] ?? data['order']),
          fallbackPriceAmount: _doubleOf(
            data['fallbackPriceAmount'] ?? data['price'],
          ),
          fallbackCurrency: data['fallbackCurrency']?.toString() ?? 'TRY',
          duration: Duration(
            minutes: _intOf(data['durationMinutes'], fallback: 30),
          ),
          active: data['active'] != false,
          title: data['title']?.toString() ?? '',
        ),
      );
    }
    parsed.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return parsed.isEmpty ? List<BoostPack>.from(storefrontPacks) : parsed;
  }

  static int _intOf(Object? value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double _doubleOf(Object? value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
