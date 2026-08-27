import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/boost/domain/config/boost_pack_catalog.dart';
import 'package:mevora/features/boost/domain/services/boost_credit_service.dart';

void main() {
  test('storefront packs are Smart Boost Starter / Popular / Power', () {
    expect(
      BoostPackCatalog.durationFor(BoostPackCatalog.starter30m).inMinutes,
      30,
    );
    expect(
      BoostPackCatalog.durationFor(BoostPackCatalog.popular1h).inHours,
      1,
    );
    expect(
      BoostPackCatalog.durationFor(BoostPackCatalog.power24h).inHours,
      24,
    );
    expect(
      BoostPackCatalog.storefrontPacks.map((pack) => pack.productId),
      [
        BoostPackCatalog.starter30m,
        BoostPackCatalog.popular1h,
        BoostPackCatalog.power24h,
      ],
    );
    expect(BoostPackCatalog.isAllowed('com.other.boost'), isFalse);
    expect(BoostPackCatalog.isAllowed(BoostPackCatalog.pack5), isTrue);
  });

  test('catalog parse keeps duration packs and skips invalid rows', () {
    final packs = BoostPackCatalog.parse([
      {
        'productId': BoostPackCatalog.starter30m,
        'durationMinutes': 30,
        'displayOrder': 0,
        'storefront': true,
      },
      {'productId': 'bad', 'boostCount': 0},
      {
        'sku': BoostPackCatalog.popular1h,
        'durationMinutes': 60,
        'order': 1,
        'storefront': true,
      },
    ]);
    expect(packs.map((pack) => pack.productId), [
      BoostPackCatalog.starter30m,
      BoostPackCatalog.popular1h,
    ]);
  });

  test('legacy credit packs still credit wallet and are not on the storefront', () {
    const service = BoostCreditService();
    final first = service.credit(
      productId: BoostPackCatalog.pack10,
      currentBalance: 2,
      alreadyCredited: false,
    );
    expect(first.shouldCredit, isTrue);
    expect(first.added, 10);
    expect(first.balance, 12);

    final again = service.credit(
      productId: BoostPackCatalog.pack10,
      currentBalance: 12,
      alreadyCredited: true,
    );
    expect(again.alreadyProcessed, isTrue);

    final duration = service.credit(
      productId: BoostPackCatalog.starter30m,
      currentBalance: 2,
      alreadyCredited: false,
    );
    expect(duration.shouldCredit, isTrue);
    expect(duration.added, 0);
    expect(duration.balance, 2);
  });
}
