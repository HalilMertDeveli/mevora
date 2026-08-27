import 'package:mevora/features/boost/domain/entities/boost_pack.dart';

/// Offline / default Boost packs. Firestore `boostProducts` is live source.
/// Prices are never stored here — store provides them.
abstract final class BoostPackCatalog {
  static const String starter30m = 'mevora_smart_boost_30m';
  static const String popular1h = 'mevora_smart_boost_1h';
  static const String power24h = 'mevora_smart_boost_24h';
  static const String week = 'mevora_boost_7_days';
  static const String month = 'mevora_boost_1_month';
  static const String year = 'mevora_boost_1_year';

  static const String legacyProductId = 'com.mevora.app.boost';
  static const String pack1 = 'com.mevora.app.boost.1';
  static const String pack5 = 'com.mevora.app.boost.5';
  static const String pack10 = 'com.mevora.app.boost.10';

  static const Duration starterDuration = Duration(minutes: 30);
  static const Duration popularDuration = Duration(hours: 1);
  static const Duration powerDuration = Duration(hours: 24);
  static const Duration weekDuration = Duration(days: 7);
  static const Duration monthDuration = Duration(days: 30);
  static const Duration yearDuration = Duration(days: 365);
  static const Duration legacyDuration = Duration(minutes: 30);

  static const List<BoostPack> defaults = [
    BoostPack(
      productId: starter30m,
      displayOrder: 0,
      duration: starterDuration,
      title: 'Starter',
    ),
    BoostPack(
      productId: popular1h,
      displayOrder: 1,
      duration: popularDuration,
      featured: true,
      title: 'Popular',
    ),
    BoostPack(
      productId: power24h,
      displayOrder: 2,
      duration: powerDuration,
      title: 'Power',
    ),
    BoostPack(
      productId: week,
      displayOrder: 10,
      duration: weekDuration,
      storefront: false,
      title: '1 Week',
    ),
    BoostPack(
      productId: month,
      displayOrder: 11,
      duration: monthDuration,
      storefront: false,
      title: '1 Month',
    ),
    BoostPack(
      productId: year,
      displayOrder: 12,
      duration: yearDuration,
      storefront: false,
      title: '1 Year',
    ),
    BoostPack(
      productId: pack1,
      boostCount: 1,
      displayOrder: 90,
      duration: legacyDuration,
      storefront: false,
      title: '1 Boost',
    ),
    BoostPack(
      productId: pack5,
      boostCount: 5,
      displayOrder: 91,
      duration: legacyDuration,
      storefront: false,
      title: '5 Boost',
    ),
    BoostPack(
      productId: pack10,
      boostCount: 10,
      displayOrder: 92,
      duration: legacyDuration,
      storefront: false,
      title: '10 Boost',
    ),
    BoostPack(
      productId: legacyProductId,
      boostCount: 1,
      displayOrder: 99,
      duration: legacyDuration,
      storefront: false,
      title: '1 Boost',
    ),
  ];

  static const Set<String> skus = {
    starter30m,
    popular1h,
    power24h,
    week,
    month,
    year,
    legacyProductId,
    pack1,
    pack5,
    pack10,
  };

  static const Set<String> storefrontSkus = {
    starter30m,
    popular1h,
    power24h,
  };

  static List<BoostPack> get storefrontPacks => defaults
      .where((pack) => pack.storefront && pack.active)
      .toList()
    ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

  static BoostPack? packFor(String productId, {List<BoostPack>? catalog}) {
    final source = catalog ?? defaults;
    for (final pack in source) {
      if (pack.productId == productId && pack.active && _isGrant(pack)) {
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

  static Duration durationFor(String productId, {List<BoostPack>? catalog}) {
    return packFor(productId, catalog: catalog)?.duration ?? Duration.zero;
  }

  static List<BoostPack> parse(Object? raw, {bool storefrontOnly = true}) {
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
      if (productId == null || productId.isEmpty) {
        continue;
      }
      final duration = _durationOf(data);
      final boostCount = _intOf(data['boostCount'] ?? data['count']);
      if (duration == Duration.zero && boostCount < 1) {
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
          duration: duration == Duration.zero ? legacyDuration : duration,
          active: data['active'] != false,
          storefront: data['storefront'] != false,
          featured: data['featured'] == true,
          title: data['title']?.toString() ?? '',
        ),
      );
    }
    parsed.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    if (parsed.isEmpty) {
      return List<BoostPack>.from(storefrontPacks);
    }
    if (!storefrontOnly) {
      return parsed.where((pack) => pack.active).toList();
    }
    final visible = parsed
        .where(
          (pack) =>
              pack.storefront &&
              pack.active &&
              pack.duration.inMinutes >= 30,
        )
        .toList();
    return visible.isEmpty ? List<BoostPack>.from(storefrontPacks) : visible;
  }

  static bool _isGrant(BoostPack pack) {
    return pack.duration > Duration.zero || pack.boostCount > 0;
  }

  static Duration _durationOf(Map<Object?, Object?> data) {
    final days = _intOf(data['durationDays'] ?? data['days']);
    if (days > 0) {
      return Duration(days: days);
    }
    final ms = _intOf(data['durationMs']);
    if (ms > 0) {
      return Duration(milliseconds: ms);
    }
    final minutes = _intOf(data['durationMinutes']);
    if (minutes > 0) {
      return Duration(minutes: minutes);
    }
    return Duration.zero;
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
