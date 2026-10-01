import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/boost/data/datasources/store_purchase_data_source.dart';
import 'package:mevora/features/boost/data/repositories/purchase_repository_impl.dart';
import 'package:mevora/features/boost/domain/config/boost_product_config.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/features/boost/domain/entities/boost_credit_result.dart';
import 'package:mevora/features/boost/domain/entities/boost_product.dart';
import 'package:mevora/features/boost/domain/entities/store_transaction.dart';

import '../../helpers/fake_purchase_repository.dart';
import '../../helpers/fake_store_purchase.dart';

/// An account that signs in and out while the repository is alive.
class _Uid implements AuthUidSource {
  _Uid([this.currentUid]);

  final StreamController<String?> _changes =
      StreamController<String?>.broadcast(sync: true);

  @override
  String? currentUid;

  @override
  Stream<String?> watchUid() => _changes.stream;

  void signIn(String uid) {
    currentUid = uid;
    _changes.add(uid);
  }

  void signOut() {
    currentUid = null;
    _changes.add(null);
  }
}

void main() {
  late FakeStorePurchaseDataSource store;
  late FakePurchaseRemoteDataSource remote;
  late FakeUidSource uid;
  late PurchaseRepositoryImpl repository;

  final now = DateTime.utc(2026, 8, 18, 12);
  final active = Boost(
    boostId: 'b1',
    userId: 'u1',
    productId: 'com.mevora.app.boost',
    purchaseId: 'android_GPA.1234',
    status: BoostStatus.active,
    createdAt: now,
    startedAt: now,
    expiresAt: now.add(const Duration(minutes: 30)),
  );

  setUp(() {
    store = FakeStorePurchaseDataSource();
    remote = FakePurchaseRemoteDataSource(
      verifyResult: const BoostCreditResult(
        purchaseId: 'android_GPA.1234',
        productId: 'com.mevora.app.boost',
        boostCount: 1,
        balance: 1,
      ),
    );
    uid = FakeUidSource('u1');
    repository = PurchaseRepositoryImpl(
      store: store,
      remote: remote,
      uidSource: uid,
      clock: () => now,
      restoreWindow: Duration.zero,
    );
  });

  tearDown(() async {
    await store.dispose();
  });

  test('loads localized store product and never invents a price', () async {
    final result = await repository.getBoostProduct();
    expect(result, isA<Success<BoostProduct>>());
    final product = (result as Success<BoostProduct>).value;
    expect(product.localizedPrice, '₺29,99');
    expect(product.currency, 'TRY');
  });

  test('pack catalog uses store prices when present and fallbacks when store is down', () async {
    store.available = false;
    final result = await repository.getBoostProducts();
    expect(result, isA<Success<List<BoostProduct>>>());
    final packs = (result as Success<List<BoostProduct>>).value;
    expect(packs.map((pack) => pack.durationDays), [7, 30, 365]);
    expect(packs.first.available, isFalse);
  });

  test('store unavailable maps to a human purchase failure', () async {
    store.available = false;
    final result = await repository.getBoostProduct();
    expect(result, isA<Err<BoostProduct>>());
    expect((result as Err).failure, isA<PurchaseFailure>());
    expect(
      ((result as Err).failure as PurchaseFailure).kind,
      PurchaseErrorKind.unavailable,
    );
  });

  test('purchase then verify activates once; duplicate verify hits remote once per call', () async {
    final product =
        (await repository.getBoostProduct() as Success<BoostProduct>).value;
    final purchased = await repository.purchaseBoost(product);
    expect(purchased, isA<Success<StoreTransaction>>());
    final tx = (purchased as Success<StoreTransaction>).value;
    final first = await repository.verifyBoostPurchase(userId: 'u1', transaction: tx);
    expect(first, isA<Success<BoostCreditResult>>());
    expect(remote.verifyCalls, 1);
    expect(store.completed, isNull);
    await repository.completeStoreTransaction(tx);
    expect(store.completed?.transactionId, 'GPA.1234');
  });

  test('cached active boost is reused without another remote read', () async {
    remote.active = active;
    final first = await repository.getActiveBoost('u1');
    final second = await repository.getActiveBoost('u1');
    expect(first.valueOrNull?.boostId, 'b1');
    expect(second.valueOrNull?.boostId, 'b1');
  });

  test('expired cached boost is not treated as active', () async {
    remote.active = Boost(
      boostId: 'b1',
      userId: 'u1',
      productId: 'com.mevora.app.boost',
      purchaseId: 'p1',
      status: BoostStatus.active,
      createdAt: now,
      startedAt: now,
      expiresAt: now.subtract(const Duration(minutes: 1)),
    );
    final result = await repository.getActiveBoost('u1');
    expect(result.valueOrNull, isNull);
  });

  test('cancelled store purchase does not call verify', () async {
    store.event = const StorePurchaseEvent(
      status: StorePurchaseStatus.cancelled,
      kind: PurchaseErrorKind.cancelled,
    );
    final product =
        (await repository.getBoostProduct() as Success<BoostProduct>).value;
    final purchased = await repository.purchaseBoost(product);
    expect((purchased as Err).failure, isA<PurchaseFailure>());
    expect(
      ((purchased as Err).failure as PurchaseFailure).kind,
      PurchaseErrorKind.cancelled,
    );
  });

  group('the store stream is shared with Premium', () {
    // in_app_purchase has one purchase stream for the whole app, so a Premium
    // subscription reports on the stream the Boost flow listens to.
    const premium = StoreTransaction(
      platform: PurchasePlatform.android,
      productId: 'mevora_premium',
      transactionId: 'GPA.premium',
      purchaseToken: 'premium-token',
    );

    test('a Premium purchase is never taken for the Boost purchase', () async {
      store.eventsBeforePurchase = const [
        StorePurchaseEvent(
          status: StorePurchaseStatus.purchased,
          transaction: premium,
        ),
        StorePurchaseEvent(
          status: StorePurchaseStatus.restored,
          transaction: premium,
        ),
      ];
      final product =
          (await repository.getBoostProduct() as Success<BoostProduct>).value;
      final purchased = await repository.purchaseBoost(product);
      expect(purchased, isA<Success<StoreTransaction>>());
      final tx = (purchased as Success<StoreTransaction>).value;
      expect(tx.productId, 'com.mevora.app.boost');
      expect(tx.transactionId, 'GPA.1234');
    });

    test('a Premium cancellation does not end the Boost purchase', () async {
      store.eventsBeforePurchase = const [
        StorePurchaseEvent(
          status: StorePurchaseStatus.cancelled,
          transaction: premium,
          kind: PurchaseErrorKind.cancelled,
        ),
      ];
      final product =
          (await repository.getBoostProduct() as Success<BoostProduct>).value;
      final purchased = await repository.purchaseBoost(product);
      expect(purchased, isA<Success<StoreTransaction>>());
    });

    test(
      'a store failure that names no product still ends the Boost purchase',
      () async {
        // Play reports a failed or cancelled sheet without a product id.
        store.event = const StorePurchaseEvent(
          status: StorePurchaseStatus.error,
          kind: PurchaseErrorKind.failed,
        );
        final product =
            (await repository.getBoostProduct() as Success<BoostProduct>).value;
        final purchased = await repository.purchaseBoost(product);
        expect(
          ((purchased as Err).failure as PurchaseFailure).kind,
          PurchaseErrorKind.failed,
        );
      },
    );

    test(
      'restore never verifies or completes a Premium subscription',
      () async {
        store.restoreEvents = const [
          StorePurchaseEvent(
            status: StorePurchaseStatus.restored,
            transaction: premium,
          ),
        ];
        await repository.restorePurchases('u1');
        expect(remote.verifyCalls, 0);
        expect(store.completions, isEmpty);
      },
    );
  });

  group('a purchase the server has not confirmed stays in the store', () {
    const unfinished = StorePurchaseEvent(
      status: StorePurchaseStatus.restored,
      transaction: StoreTransaction(
        platform: PurchasePlatform.android,
        productId: 'com.mevora.app.boost',
        transactionId: 'GPA.unfinished',
        purchaseToken: 'unfinished-token',
      ),
    );

    test(
      'restore submits it to the server and completes it once confirmed',
      () async {
        store.restoreEvents = const [unfinished];
        remote.verifyDelay = const Duration(milliseconds: 20);
        remote.verifyResult = BoostCreditResult(
          purchaseId: 'android_hash',
          productId: 'com.mevora.app.boost',
          boostCount: 0,
          balance: 0,
          boost: active,
        );

        await repository.restorePurchases('u1');

        // The restore has waited for the server's answer: by the time it
        // returns, the purchase is verified and only then consumed.
        expect(remote.verifyCalls, 1);
        expect(remote.lastTransaction?.purchaseToken, 'unfinished-token');
        expect(store.completions.map((tx) => tx.transactionId), [
          'GPA.unfinished',
        ]);
      },
    );

    test(
      'restore leaves it unconsumed when the server still cannot confirm',
      () async {
        store.restoreEvents = const [unfinished];
        remote.verifyError = const PurchaseException(
          'unavailable',
          kind: PurchaseErrorKind.storeDown,
        );

        final result = await repository.restorePurchases('u1');

        expect(result, isA<Success<Boost?>>());
        expect(remote.verifyCalls, 1);
        expect(store.completions, isEmpty);
      },
    );

    test('a redelivered purchase is submitted once per restore', () async {
      store.restoreEvents = const [unfinished, unfinished];
      await repository.restorePurchases('u1');
      expect(remote.verifyCalls, 1);
      expect(store.completions, hasLength(1));
    });
  });

  group('a purchase an earlier session paid for but never confirmed', () {
    const leftOver = StoreTransaction(
      platform: PurchasePlatform.android,
      productId: 'com.mevora.app.boost',
      transactionId: 'GPA.left-over',
      purchaseToken: 'left-over-token',
    );

    setUp(() async {
      // The repository built for every test has made its own start-up check
      // by now; these tests count the ones they cause.
      await pumpEventQueue();
      store.outstandingQueries = 0;
    });

    /// A repository whose account can change after it is built.
    PurchaseRepositoryImpl repositoryFor(_Uid account) {
      return PurchaseRepositoryImpl(
        store: store,
        remote: remote,
        uidSource: account,
        clock: () => now,
        restoreWindow: Duration.zero,
      );
    }

    test('is submitted to the server and completed once confirmed', () async {
      final recovering = repositoryFor(_Uid('u1'));
      store.outstanding = const [leftOver];

      await recovering.recoverUnfinishedPurchases();

      expect(remote.verifyCalls, 1);
      expect(remote.lastTransaction?.purchaseToken, 'left-over-token');
      expect(store.completions.map((tx) => tx.transactionId), [
        'GPA.left-over',
      ]);
    });

    test(
      'asks the store directly and never replays the shared stream',
      () async {
        final recovering = repositoryFor(_Uid('u1'));
        store.outstanding = const [leftOver];

        await recovering.recoverUnfinishedPurchases();

        expect(store.outstandingQueries, 1);
        expect(store.restored, isFalse);
      },
    );

    test('stays unconsumed when the server still cannot confirm', () async {
      final recovering = repositoryFor(_Uid('u1'));
      store.outstanding = const [leftOver];
      remote.verifyError = const PurchaseException(
        'unavailable',
        kind: PurchaseErrorKind.storeDown,
      );

      await recovering.recoverUnfinishedPurchases();

      expect(remote.verifyCalls, 1);
      expect(store.completions, isEmpty);
    });

    test(
      'the Boost it bought shows at once, even if the store step fails',
      () async {
        final recovering = repositoryFor(_Uid('u1'));
        // The Boost screen was read before the recovery: no Boost, cached.
        expect((await recovering.getActiveBoost('u1')).valueOrNull, isNull);
        store.outstanding = const [leftOver];
        store.completeError = const PurchaseException(
          'not owned',
          kind: PurchaseErrorKind.failed,
        );
        remote.verifyResult = BoostCreditResult(
          purchaseId: 'android_hash',
          productId: 'com.mevora.app.boost',
          boostCount: 0,
          balance: 0,
          boost: active,
        );

        await recovering.recoverUnfinishedPurchases();

        expect((await recovering.getActiveBoost('u1')).valueOrNull?.boostId, 'b1');
      },
    );

    test('a Premium purchase the store also holds is left alone', () async {
      final recovering = repositoryFor(_Uid('u1'));
      store.outstanding = const [
        StoreTransaction(
          platform: PurchasePlatform.android,
          productId: 'mevora_premium',
          transactionId: 'GPA.premium',
          purchaseToken: 'premium-token',
        ),
      ];

      await recovering.recoverUnfinishedPurchases();

      expect(remote.verifyCalls, 0);
      expect(store.completions, isEmpty);
    });

    test('the same purchase listed twice is submitted once', () async {
      final recovering = repositoryFor(_Uid('u1'));
      store.outstanding = const [leftOver, leftOver];

      await recovering.recoverUnfinishedPurchases();

      expect(remote.verifyCalls, 1);
      expect(store.completions, hasLength(1));
    });

    test('nothing is asked of the store while nobody is signed in', () async {
      final recovering = repositoryFor(_Uid());
      store.outstanding = const [leftOver];

      await recovering.recoverUnfinishedPurchases();

      expect(store.outstandingQueries, 0);
      expect(remote.verifyCalls, 0);
    });

    test('a store that cannot answer does not break start-up', () async {
      final recovering = repositoryFor(_Uid('u1'));
      store.outstandingError = StateError('billing unavailable');

      await recovering.recoverUnfinishedPurchases();

      expect(remote.verifyCalls, 0);
    });

    test('two overlapping checks submit it once', () async {
      final recovering = repositoryFor(_Uid('u1'));
      store.outstanding = const [leftOver];
      remote.verifyDelay = const Duration(milliseconds: 20);

      await Future.wait([
        recovering.recoverUnfinishedPurchases(),
        recovering.recoverUnfinishedPurchases(),
      ]);

      expect(remote.verifyCalls, 1);
    });

    test('runs when an account signs in, once per account', () async {
      final account = _Uid();
      repositoryFor(account);
      store.outstanding = const [leftOver];

      account.signIn('u1');
      await pumpEventQueue();
      expect(remote.verifyCalls, 1);
      expect(store.completions, hasLength(1));

      // The same account reported again — a token refresh — is not a sign-in.
      account.signIn('u1');
      await pumpEventQueue();
      expect(store.outstandingQueries, 1);

      account.signOut();
      await pumpEventQueue();
      expect(store.outstandingQueries, 1);

      account.signIn('u2');
      await pumpEventQueue();
      expect(store.outstandingQueries, 2);
    });

    test(
      'runs at app start for an account that is already signed in',
      () async {
        store.outstanding = const [leftOver];

        // FakeUidSource reports its account as soon as it is listened to, the
        // way Firebase Auth does for a restored session.
        PurchaseRepositoryImpl(
          store: store,
          remote: remote,
          uidSource: FakeUidSource('u1'),
          clock: () => now,
        );
        await pumpEventQueue();

        expect(remote.verifyCalls, 1);
        expect(remote.lastTransaction?.purchaseToken, 'left-over-token');
        expect(store.restored, isFalse);
      },
    );

    test(
      'does not take over a purchase that is on screen right now',
      () async {
        final recovering = repositoryFor(_Uid('u1'));
        final product =
            (await recovering.getBoostProduct() as Success<BoostProduct>).value;
        store.outstanding = [store.event.transaction!];
        store.buyGate = Completer<void>();

        final buying = recovering.purchaseBoost(product);
        await pumpEventQueue();
        await recovering.recoverUnfinishedPurchases();
        store.buyGate!.complete();
        await buying;

        // The purchase flow verifies and completes its own purchase.
        expect(remote.verifyCalls, 0);
        expect(store.completions, isEmpty);
      },
    );
  });

  test('uid mismatch refuses verification', () async {
    uid.currentUid = 'other';
    final result = await repository.verifyBoostPurchase(
      userId: 'u1',
      transaction: store.event.transaction!,
    );
    expect(result, isA<Err<BoostCreditResult>>());
    expect(remote.verifyCalls, 0);
  });
}
