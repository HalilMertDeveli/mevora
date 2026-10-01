import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mevora/features/boost/data/datasources/in_app_store_purchase_data_source.dart';
import 'package:mevora/features/boost/data/services/apple_purchase_service.dart';
import 'package:mevora/features/boost/data/services/google_purchase_service.dart';
import 'package:mevora/features/boost/domain/entities/store_transaction.dart';

const String _week = 'mevora_boost_7_days';

/// The store plugin as the data source sees it, with nothing behind it.
class _FakeStore implements InAppPurchase {
  final StreamController<List<PurchaseDetails>> stream =
      StreamController<List<PurchaseDetails>>.broadcast(sync: true);

  bool available = true;
  int availabilityChecks = 0;
  int restoreCalls = 0;
  final List<PurchaseDetails> completed = <PurchaseDetails>[];

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => stream.stream;

  @override
  Future<bool> isAvailable() async {
    availabilityChecks += 1;
    return available;
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restoreCalls += 1;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Google extends GooglePurchaseService {
  _Google(InAppPurchase store) : super(store: store);

  final List<PurchaseDetails> consumed = <PurchaseDetails>[];

  @override
  Future<void> consume(PurchaseDetails details) async {
    consumed.add(details);
  }
}

PurchaseDetails _purchase({
  String orderId = 'GPA.1',
  String token = 'token-1',
  String productId = _week,
  PurchaseStatus status = PurchaseStatus.purchased,
}) {
  return PurchaseDetails(
    purchaseID: orderId,
    productID: productId,
    verificationData: PurchaseVerificationData(
      localVerificationData: '{}',
      serverVerificationData: token,
      source: 'google_play',
    ),
    transactionDate: '1790000000000',
    status: status,
  );
}

void main() {
  late _FakeStore store;
  late _Google google;
  late int queries;
  late List<PurchaseDetails> held;

  InAppStorePurchaseDataSource dataSource(PurchasePlatform platform) {
    return InAppStorePurchaseDataSource(
      store: store,
      apple: ApplePurchaseService(store: store),
      google: google,
      platformOverride: platform,
      outstandingPurchases: () async {
        queries += 1;
        return held;
      },
    );
  }

  setUp(() {
    store = _FakeStore();
    google = _Google(store);
    queries = 0;
    held = <PurchaseDetails>[];
  });

  tearDown(() async {
    await store.stream.close();
  });

  group('purchases Play still holds unconsumed', () {
    test('are returned with the token the server verifies', () async {
      held = <PurchaseDetails>[_purchase(orderId: 'GPA.9', token: 'token-9')];
      final source = dataSource(PurchasePlatform.android);

      final outstanding = await source.outstandingPurchases();

      expect(outstanding, hasLength(1));
      expect(outstanding.single.platform, PurchasePlatform.android);
      expect(outstanding.single.productId, _week);
      expect(outstanding.single.transactionId, 'GPA.9');
      expect(outstanding.single.purchaseToken, 'token-9');
    });

    test('a payment that has not settled yet is not one of them', () async {
      held = <PurchaseDetails>[
        _purchase(token: 'unpaid', status: PurchaseStatus.pending),
        _purchase(orderId: 'GPA.2', token: 'paid'),
      ];
      final source = dataSource(PurchasePlatform.android);

      final outstanding = await source.outstandingPurchases();

      expect(outstanding.map((tx) => tx.purchaseToken), <String>['paid']);
    });

    test('can be completed once the server has confirmed them', () async {
      final details = _purchase();
      held = <PurchaseDetails>[details];
      final source = dataSource(PurchasePlatform.android);

      final outstanding = await source.outstandingPurchases();
      await source.complete(outstanding.single);

      expect(google.consumed, <PurchaseDetails>[details]);
    });

    test('are read without replaying the shared purchase stream', () async {
      held = <PurchaseDetails>[_purchase()];
      final source = dataSource(PurchasePlatform.android);
      final events = <Object>[];
      final sub = source.purchaseEvents.listen(events.add);

      await source.outstandingPurchases();
      await pumpEventQueue();
      await sub.cancel();

      expect(store.restoreCalls, 0);
      expect(events, isEmpty);
    });

    test('a store that is not available is not queried', () async {
      store.available = false;
      held = <PurchaseDetails>[_purchase()];
      final source = dataSource(PurchasePlatform.android);

      expect(await source.outstandingPurchases(), isEmpty);
      expect(queries, 0);
    });
  });

  test(
    'iOS is never asked: nothing can raise an App Store sign-in prompt',
    () async {
      held = <PurchaseDetails>[_purchase()];
      final source = dataSource(PurchasePlatform.ios);

      expect(await source.outstandingPurchases(), isEmpty);
      expect(queries, 0);
      expect(store.restoreCalls, 0);
      expect(store.availabilityChecks, 0);
    },
  );
}
