import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/boost/data/datasources/store_purchase_data_source.dart';
import 'package:mevora/features/boost/data/repositories/purchase_repository_impl.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/features/boost/domain/entities/boost_product.dart';
import 'package:mevora/features/boost/domain/entities/store_transaction.dart';

import '../../helpers/fake_purchase_repository.dart';
import '../../helpers/fake_store_purchase.dart';

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
    remote = FakePurchaseRemoteDataSource(verifyResult: active);
    uid = FakeUidSource('u1');
    repository = PurchaseRepositoryImpl(
      store: store,
      remote: remote,
      uidSource: uid,
      clock: () => now,
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
    expect(first, isA<Success<Boost>>());
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

  test('uid mismatch refuses verification', () async {
    uid.currentUid = 'other';
    final result = await repository.verifyBoostPurchase(
      userId: 'u1',
      transaction: store.event.transaction!,
    );
    expect(result, isA<Err<Boost>>());
    expect(remote.verifyCalls, 0);
  });
}
