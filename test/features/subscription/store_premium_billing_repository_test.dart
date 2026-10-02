import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
// The Play-specific product and purchase types live in the Android
// implementation package, which `in_app_purchase` depends on and re-exports
// nothing from.
// ignore: depend_on_referenced_packages
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
// ignore: depend_on_referenced_packages
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/subscription/data/repositories/store_premium_billing_repository.dart';
import 'package:mevora/features/subscription/domain/config/premium_product_config.dart';
import 'package:mevora/features/subscription/domain/entities/premium_plan.dart';
import 'package:mevora/features/subscription/domain/repositories/premium_billing_repository.dart';

const String _premium = 'mevora_premium';
const String _boost = 'mevora_boost_7_days';

/// Play Billing as the repository sees it, with nothing behind it.
class _FakeStore implements InAppPurchase {
  final StreamController<List<PurchaseDetails>> stream =
      StreamController<List<PurchaseDetails>>.broadcast(sync: true);

  List<ProductDetails> products = <ProductDetails>[];
  List<PurchaseDetails> restorable = <PurchaseDetails>[];
  final List<PurchaseParam> bought = <PurchaseParam>[];
  final List<PurchaseDetails> completed = <PurchaseDetails>[];

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => stream.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    return ProductDetailsResponse(
      productDetails: products
          .where((product) => identifiers.contains(product.id))
          .toList(),
      notFoundIDs: const <String>[],
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    bought.add(purchaseParam);
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase);
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    stream.add(restorable);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Backend implements BackendCallable {
  _Backend(this.reply);

  /// The callable's answer; set [failure] to make it throw instead.
  Map<String, dynamic> reply;
  Object? failure;
  final List<Map<String, dynamic>> calls = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    calls.add(Map<String, dynamic>.from(data ?? const <String, dynamic>{}));
    final failure = this.failure;
    if (failure != null) {
      throw failure;
    }
    return reply;
  }
}

class _Uid implements AuthUidSource {
  _Uid([this.currentUid]);

  final StreamController<String?> changes = StreamController<String?>.broadcast(
    sync: true,
  );

  @override
  String? currentUid;

  @override
  Stream<String?> watchUid() => changes.stream;
}

const Map<String, dynamic> _granted = <String, dynamic>{
  'ok': true,
  'isPremium': true,
  'status': 'active',
};

Map<String, dynamic> _refused(String reason) => <String, dynamic>{
  'ok': false,
  'isPremium': false,
  'reason': reason,
};

SubscriptionOfferDetailsWrapper _offer(
  String basePlanId,
  String billingPeriod,
  String price, {
  String? offerId,
}) {
  return SubscriptionOfferDetailsWrapper(
    basePlanId: basePlanId,
    offerId: offerId,
    offerTags: const <String>[],
    offerIdToken: offerId == null
        ? 'offer-$basePlanId'
        : 'offer-$basePlanId-$offerId',
    pricingPhases: <PricingPhaseWrapper>[
      PricingPhaseWrapper(
        billingCycleCount: 0,
        billingPeriod: billingPeriod,
        formattedPrice: price,
        priceAmountMicros: 1000000,
        priceCurrencyCode: 'TRY',
        recurrenceMode: RecurrenceMode.infiniteRecurring,
      ),
    ],
  );
}

/// One Play subscription with a base plan per offer, the way the plugin
/// reports it: a product detail per offer, all sharing the product id.
List<ProductDetails> _subscription(
  List<SubscriptionOfferDetailsWrapper> offers,
) {
  return GooglePlayProductDetails.fromProductDetails(
    ProductDetailsWrapper(
      description: 'See who likes you',
      name: 'Premium',
      productId: _premium,
      productType: ProductType.subs,
      title: 'Mevora Premium',
      subscriptionOfferDetails: offers,
    ),
  );
}

List<ProductDetails> _monthlyAndYearly() =>
    _subscription(<SubscriptionOfferDetailsWrapper>[
      _offer('monthly', 'P1M', '₺99,00'),
      _offer('yearly', 'P1Y', '₺799,00'),
    ]);

PurchaseDetails _playPurchase({
  String productId = _premium,
  String token = 'token-1',
  PurchaseStateWrapper state = PurchaseStateWrapper.purchased,
  bool acknowledged = false,
  PurchaseStatus? status,
}) {
  final details = GooglePlayPurchaseDetails.fromPurchase(
    PurchaseWrapper(
      orderId: 'GPA.$token',
      packageName: 'com.mevora.app',
      purchaseTime: 0,
      purchaseToken: token,
      signature: '',
      products: <String>[productId],
      isAutoRenewing: true,
      originalJson: '{}',
      isAcknowledged: acknowledged,
      purchaseState: state,
    ),
  ).single;
  if (status != null) {
    details.status = status;
  }
  return details;
}

/// What Play emits when its sheet closes without a purchase.
PurchaseDetails _sheetClosed(PurchaseStatus status) {
  return PurchaseDetails(
    purchaseID: '',
    productID: '',
    status: status,
    transactionDate: null,
    verificationData: PurchaseVerificationData(
      localVerificationData: '',
      serverVerificationData: '',
      source: 'google_play',
    ),
  );
}

const PremiumProductConfig _config = PremiumProductConfig(
  android: <PremiumProductRef>[
    PremiumProductRef(productId: _premium, basePlanId: 'monthly'),
    PremiumProductRef(productId: _premium, basePlanId: 'yearly'),
  ],
);

class _Harness {
  _Harness({
    Map<String, dynamic> reply = _granted,
    PremiumProductConfig config = _config,
    AuthUidSource? uidSource,
    List<PurchaseDetails> outstanding = const <PurchaseDetails>[],
  }) : backend = _Backend(reply),
       outstanding = List<PurchaseDetails>.of(outstanding) {
    store.products = _monthlyAndYearly();
    repository = StorePremiumBillingRepository(
      backend: backend,
      config: config,
      store: store,
      platformOverride: PremiumPlatform.android,
      uidSource: uidSource,
      outstandingPurchases: () async => this.outstanding,
    );
  }

  final _FakeStore store = _FakeStore();
  final _Backend backend;
  final List<PurchaseDetails> outstanding;
  late final StorePremiumBillingRepository repository;

  Future<PremiumPlan> plan(String basePlanId) async {
    final plans = await repository.loadPlans();
    return plans.singleWhere((plan) => plan.basePlanId == basePlanId);
  }

  /// Starts a buy and returns once the store sheet is "open".
  Future<Future<PremiumVerificationResult>> buy(String basePlanId) async {
    final future = repository.purchase(await plan(basePlanId));
    // Keeps an expected failure from surfacing as an unhandled async error
    // before the test gets to assert on it.
    unawaited(future.then<void>((_) {}, onError: (Object _) {}));
    await pumpEventQueue();
    return future;
  }

  Future<void> dispose() => repository.dispose();
}

void main() {
  late _Harness harness;

  tearDown(() async {
    await harness.dispose();
  });

  group('D3 — acknowledge only what the backend accounts for', () {
    test('a granted purchase is completed', () async {
      harness = _Harness();
      final result = await harness.buy('monthly');
      harness.store.stream.add(<PurchaseDetails>[_playPurchase()]);

      expect((await result).isPremium, isTrue);
      expect(harness.store.completed, hasLength(1));
    });

    test(
      'a failed verification call leaves the purchase unacknowledged',
      () async {
        harness = _Harness();
        harness.backend.failure = StateError('unavailable');
        final result = await harness.buy('monthly');
        harness.store.stream.add(<PurchaseDetails>[_playPurchase()]);

        await expectLater(
          result,
          throwsA(
            isA<PremiumBillingException>().having(
              (error) => error.failure,
              'failure',
              PremiumPurchaseFailure.transient,
            ),
          ),
        );
        expect(harness.store.completed, isEmpty);
      },
    );

    for (final reason in <String>['unavailable', 'not_configured']) {
      test('"$reason" answered by an older backend is retryable, '
          'not handled', () async {
        harness = _Harness(reply: _refused(reason));
        final result = await harness.buy('monthly');
        harness.store.stream.add(<PurchaseDetails>[_playPurchase()]);

        await expectLater(
          result,
          throwsA(
            isA<PremiumBillingException>().having(
              (error) => error.failure,
              'failure',
              PremiumPurchaseFailure.transient,
            ),
          ),
        );
        expect(harness.store.completed, isEmpty);
      });
    }

    for (final reason in <String>[
      'unknown_product',
      'unknown_base_plan',
      'package_mismatch',
      'invalid',
      'account_mismatch',
      'unknown_state',
    ]) {
      test('"$reason" wrote no entitlement, so nothing is completed', () async {
        harness = _Harness(reply: _refused(reason));
        final result = await harness.buy('monthly');
        harness.store.stream.add(<PurchaseDetails>[_playPurchase()]);

        final answer = await result;
        expect(answer.ok, isFalse);
        expect(answer.reason, reason);
        expect(harness.store.completed, isEmpty);
      });
    }

    test('a purchase another account already holds is completed', () async {
      // The entitlement exists — under the account that claimed it — so
      // nothing is left to verify and nothing is lost by finishing.
      harness = _Harness(reply: _refused('owned_by_other'));
      final result = await harness.buy('monthly');
      harness.store.stream.add(<PurchaseDetails>[_playPurchase()]);

      expect((await result).reason, 'owned_by_other');
      expect(harness.store.completed, hasLength(1));
    });

    test('restore completes only what the backend accounts for', () async {
      harness = _Harness(reply: _refused('unknown_base_plan'));
      harness.store.restorable = <PurchaseDetails>[
        _playPurchase(status: PurchaseStatus.restored),
      ];

      final result = await harness.repository.restore();

      expect(result.reason, 'unknown_base_plan');
      expect(harness.store.completed, isEmpty);
    });
  });

  group('D5 — the plan that was tapped is the plan that is bought', () {
    test('each base plan is its own plan with its own key', () async {
      harness = _Harness();
      final plans = await harness.repository.loadPlans();

      expect(plans.map((plan) => plan.planKey), <String>[
        '$_premium:monthly',
        '$_premium:yearly',
      ]);
      expect(plans.map((plan) => plan.formattedPrice), <String>[
        '₺99,00',
        '₺799,00',
      ]);
      expect(plans.map((plan) => plan.period), <PremiumPlanPeriod>[
        PremiumPlanPeriod.monthly,
        PremiumPlanPeriod.yearly,
      ]);
    });

    test('buying yearly sends the yearly offer, not the first one', () async {
      harness = _Harness();
      await harness.buy('yearly');

      final param = harness.store.bought.single as GooglePlayPurchaseParam;
      expect(param.offerToken, 'offer-yearly');
      expect(
        (param.productDetails as GooglePlayProductDetails).offerToken,
        'offer-yearly',
      );
      harness.store.stream.add(<PurchaseDetails>[
        _sheetClosed(PurchaseStatus.canceled),
      ]);
    });

    test('a base plan that is not configured is not offered', () async {
      harness = _Harness(
        config: const PremiumProductConfig(
          android: <PremiumProductRef>[
            PremiumProductRef(productId: _premium, basePlanId: 'monthly'),
          ],
        ),
      );
      final plans = await harness.repository.loadPlans();
      expect(plans.map((plan) => plan.planKey), <String>['$_premium:monthly']);
    });

    test(
      'a plan the store no longer offers is refused, never swapped',
      () async {
        harness = _Harness();
        const gone = PremiumPlan(
          productId: _premium,
          basePlanId: 'quarterly',
          title: 'Mevora Premium',
          description: '',
          formattedPrice: '₺249,00',
        );

        await expectLater(
          harness.repository.purchase(gone),
          throwsA(
            isA<PremiumBillingException>().having(
              (error) => error.failure,
              'failure',
              PremiumPurchaseFailure.productsUnavailable,
            ),
          ),
        );
        expect(harness.store.bought, isEmpty);
      },
    );

    test('a bare product id still offers every base plan', () async {
      harness = _Harness(
        config: const PremiumProductConfig(
          android: <PremiumProductRef>[PremiumProductRef(productId: _premium)],
        ),
      );
      final plans = await harness.repository.loadPlans();
      expect(plans.map((plan) => plan.basePlanId), <String>[
        'monthly',
        'yearly',
      ]);
    });

    test('a promotional offer does not become a second plan', () async {
      harness = _Harness();
      harness.store.products = _subscription(<SubscriptionOfferDetailsWrapper>[
        _offer('monthly', 'P1M', '₺0,00', offerId: 'trial'),
        _offer('monthly', 'P1M', '₺99,00'),
        _offer('yearly', 'P1Y', '₺799,00'),
      ]);

      final plans = await harness.repository.loadPlans();
      expect(plans.map((plan) => plan.planKey), <String>[
        '$_premium:monthly',
        '$_premium:yearly',
      ]);
      // The price shown is the base plan's own, and that is what is bought.
      expect(plans.first.formattedPrice, '₺99,00');

      await harness.buy('monthly');
      final param = harness.store.bought.single as GooglePlayPurchaseParam;
      expect(param.offerToken, 'offer-monthly');
      harness.store.stream.add(<PurchaseDetails>[
        _sheetClosed(PurchaseStatus.canceled),
      ]);
    });
  });

  group('D7 — only Premium purchases are touched', () {
    test('a Boost purchase is neither verified nor completed', () async {
      harness = _Harness();
      harness.store.stream.add(<PurchaseDetails>[
        _playPurchase(productId: _boost, token: 'boost-token'),
      ]);
      await pumpEventQueue();

      expect(harness.backend.calls, isEmpty);
      expect(harness.store.completed, isEmpty);
    });

    test('a Boost purchase does not resolve a Premium buy', () async {
      harness = _Harness();
      final result = await harness.buy('monthly');
      var settled = false;
      unawaited(result.whenComplete(() => settled = true));

      harness.store.stream.add(<PurchaseDetails>[
        _playPurchase(productId: _boost, token: 'boost-token'),
      ]);
      await pumpEventQueue();
      expect(settled, isFalse);

      harness.store.stream.add(<PurchaseDetails>[_playPurchase()]);
      expect((await result).isPremium, isTrue);
      expect(harness.backend.calls, hasLength(1));
    });

    test('restore verifies Premium purchases only', () async {
      harness = _Harness();
      harness.store.restorable = <PurchaseDetails>[
        _playPurchase(
          productId: _boost,
          token: 'boost-token',
          status: PurchaseStatus.restored,
        ),
        _playPurchase(status: PurchaseStatus.restored),
      ];

      final result = await harness.repository.restore();

      expect(result.isPremium, isTrue);
      expect(harness.backend.calls.single['purchaseToken'], 'token-1');
      expect(harness.store.completed.single.productID, _premium);
    });

    test('a sheet closed without a purchase still ends the buy', () async {
      harness = _Harness();
      final result = await harness.buy('monthly');
      harness.store.stream.add(<PurchaseDetails>[
        _sheetClosed(PurchaseStatus.canceled),
      ]);

      await expectLater(
        result,
        throwsA(
          isA<PremiumBillingException>().having(
            (error) => error.failure,
            'failure',
            PremiumPurchaseFailure.cancelled,
          ),
        ),
      );
    });
  });

  group('D10 — a pending payment', () {
    test('ends the buy as pending instead of spinning', () async {
      harness = _Harness();
      final result = await harness.buy('monthly');
      harness.store.stream.add(<PurchaseDetails>[
        _playPurchase(state: PurchaseStateWrapper.pending),
      ]);

      final answer = await result;
      expect(answer.isPending, isTrue);
      expect(answer.isPremium, isFalse);
      // Nothing has been paid for, so there is nothing to verify or finish.
      expect(harness.backend.calls, isEmpty);
      expect(harness.store.completed, isEmpty);
    });

    test('does not block the next buy', () async {
      harness = _Harness();
      final first = await harness.buy('monthly');
      harness.store.stream.add(<PurchaseDetails>[
        _playPurchase(state: PurchaseStateWrapper.pending),
      ]);
      await first;

      final second = await harness.buy('monthly');
      harness.store.stream.add(<PurchaseDetails>[
        _playPurchase(token: 'token-2'),
      ]);
      expect((await second).isPremium, isTrue);
    });

    test('is verified when the payment later settles', () async {
      harness = _Harness();
      final result = await harness.buy('monthly');
      harness.store.stream.add(<PurchaseDetails>[
        _playPurchase(state: PurchaseStateWrapper.pending),
      ]);
      await result;

      harness.store.stream.add(<PurchaseDetails>[_playPurchase()]);
      await pumpEventQueue();

      expect(harness.backend.calls.single['purchaseToken'], 'token-1');
      expect(harness.store.completed, hasLength(1));
    });
  });

  group('D10 — purchases left outstanding by an earlier session', () {
    test(
      'an unacknowledged Premium purchase is verified and completed',
      () async {
        harness = _Harness(
          outstanding: <PurchaseDetails>[_playPurchase(token: 'left-over')],
        );

        await harness.repository.reverifyOutstandingPurchases();

        expect(harness.backend.calls.single['purchaseToken'], 'left-over');
        expect(harness.store.completed, hasLength(1));
      },
    );

    test('pending, acknowledged and Boost purchases are left alone', () async {
      harness = _Harness(
        outstanding: <PurchaseDetails>[
          _playPurchase(token: 'unpaid', state: PurchaseStateWrapper.pending),
          _playPurchase(token: 'settled', acknowledged: true),
          _playPurchase(productId: _boost, token: 'boost-token'),
        ],
      );

      await harness.repository.reverifyOutstandingPurchases();

      expect(harness.backend.calls, isEmpty);
      expect(harness.store.completed, isEmpty);
    });

    test('a backend that is still failing leaves it for next time', () async {
      harness = _Harness(
        outstanding: <PurchaseDetails>[_playPurchase(token: 'left-over')],
      );
      harness.backend.failure = StateError('unavailable');

      await harness.repository.reverifyOutstandingPurchases();

      expect(harness.backend.calls, hasLength(1));
      expect(harness.store.completed, isEmpty);
    });

    test('runs when an account signs in', () async {
      final uid = _Uid();
      harness = _Harness(
        uidSource: uid,
        outstanding: <PurchaseDetails>[_playPurchase(token: 'left-over')],
      );

      uid.changes.add(null);
      await pumpEventQueue();
      expect(harness.backend.calls, isEmpty);

      uid.currentUid = 'user-1';
      uid.changes.add('user-1');
      await pumpEventQueue();

      expect(harness.backend.calls.single['purchaseToken'], 'left-over');
      expect(harness.store.completed, hasLength(1));
    });
  });

  group('D11 — a purchase is stamped with the account that made it', () {
    test('the stamp is a hash of the uid, never the uid', () async {
      harness = _Harness(uidSource: _Uid('user-1'));
      await harness.buy('monthly');

      final stamp = harness.store.bought.single.applicationUserName;
      expect(stamp, StorePremiumBillingRepository.accountIdFor('user-1'));
      // sha256("user-1") in hex — the same value the backend's
      // `premiumAccountId` computes from the caller's uid. Play allows at
      // most 64 characters here, which is exactly this.
      expect(
        stamp,
        'c6c289e49e9c05b2145860387b73bcb18df43fb09a1e4a4a9713c76c88bb541b',
      );
      expect(stamp, isNot(contains('user-1')));
      harness.store.stream.add(<PurchaseDetails>[
        _sheetClosed(PurchaseStatus.canceled),
      ]);
    });

    test('no stamp when nobody is signed in', () async {
      harness = _Harness(uidSource: _Uid());
      await harness.buy('monthly');

      expect(harness.store.bought.single.applicationUserName, isNull);
      harness.store.stream.add(<PurchaseDetails>[
        _sheetClosed(PurchaseStatus.canceled),
      ]);
    });
  });
}
