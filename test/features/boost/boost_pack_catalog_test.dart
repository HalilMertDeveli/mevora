import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/boost/domain/config/boost_pack_catalog.dart';
import 'package:mevora/features/boost/domain/services/boost_credit_service.dart';

void main() {
  test('storefront packs are 7 / 30 / 365 day grants', () {
    expect(BoostPackCatalog.durationFor(BoostPackCatalog.week).inDays, 7);
    expect(BoostPackCatalog.durationFor(BoostPackCatalog.month).inDays, 30);
    expect(BoostPackCatalog.durationFor(BoostPackCatalog.year).inDays, 365);
    expect(
      BoostPackCatalog.storefrontPacks.map((pack) => pack.productId),
      [
        BoostPackCatalog.week,
        BoostPackCatalog.month,
        BoostPackCatalog.year,
      ],
    );
    expect(BoostPackCatalog.isAllowed('com.other.boost'), isFalse);
    expect(BoostPackCatalog.isAllowed(BoostPackCatalog.pack5), isTrue);
  });

  test('catalog parse keeps duration packs and skips invalid rows', () {
    final packs = BoostPackCatalog.parse([
      {
        'productId': BoostPackCatalog.week,
        'durationDays': 7,
        'displayOrder': 0,
      },
      {'productId': 'bad', 'boostCount': 0},
      {
        'sku': BoostPackCatalog.month,
        'days': 30,
        'order': 1,
      },
    ]);
    expect(packs.map((pack) => pack.productId), [
      BoostPackCatalog.week,
      BoostPackCatalog.month,
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
      productId: BoostPackCatalog.week,
      currentBalance: 2,
      alreadyCredited: false,
    );
    expect(duration.shouldCredit, isTrue);
    expect(duration.added, 0);
    expect(duration.balance, 2);
  });
}
