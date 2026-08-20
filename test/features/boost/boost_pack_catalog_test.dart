import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/boost/domain/config/boost_pack_catalog.dart';
import 'package:mevora/features/boost/domain/services/boost_credit_service.dart';

void main() {
  test('default packs map SKUs to 1 / 5 / 10 credits', () {
    expect(BoostPackCatalog.boostCountFor(BoostPackCatalog.pack1), 1);
    expect(BoostPackCatalog.boostCountFor(BoostPackCatalog.pack5), 5);
    expect(BoostPackCatalog.boostCountFor(BoostPackCatalog.pack10), 10);
    expect(BoostPackCatalog.boostCountFor(BoostPackCatalog.legacyProductId), 1);
    expect(BoostPackCatalog.isAllowed('com.other.boost'), isFalse);
  });

  test('catalog parse uses backend JSON and skips invalid rows', () {
    final packs = BoostPackCatalog.parse([
      {
        'productId': 'com.mevora.app.boost.1',
        'boostCount': 1,
        'displayOrder': 0,
        'fallbackPriceAmount': 49.99,
      },
      {'productId': 'bad', 'boostCount': 0},
      {
        'sku': 'com.mevora.app.boost.5',
        'count': 5,
        'order': 1,
        'price': 199.99,
      },
    ]);
    expect(packs.map((pack) => pack.productId), [
      BoostPackCatalog.pack1,
      BoostPackCatalog.pack5,
    ]);
    expect(packs.first.fallbackPriceLabel, '₺49,99');
  });

  test('credit adds pack size and is idempotent on already-credited purchases', () {
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
    expect(again.shouldCredit, isFalse);
    expect(again.balance, 12);

    final unknown = service.credit(
      productId: 'com.other.boost',
      currentBalance: 2,
      alreadyCredited: false,
    );
    expect(unknown.invalidPack, isTrue);
  });
}
