import 'dart:async';

import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/features/boost/data/datasources/firebase_purchase_data_source.dart';
import 'package:mevora/features/boost/data/datasources/store_purchase_data_source.dart';
import 'package:mevora/features/boost/domain/config/boost_product_config.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/features/boost/domain/entities/boost_product.dart';
import 'package:mevora/features/boost/domain/entities/store_transaction.dart';

class FakeStorePurchaseDataSource implements StorePurchaseDataSource {
  FakeStorePurchaseDataSource({
    this.available = true,
    this.product = const BoostProduct(
      productId: 'com.mevora.app.boost',
      title: 'Mevora Boost',
      description: 'Extra discovery visibility',
      localizedPrice: '₺29,99',
      currency: 'TRY',
      available: true,
      duration: Duration(minutes: 30),
    ),
    this.event = const StorePurchaseEvent(
      status: StorePurchaseStatus.purchased,
      transaction: StoreTransaction(
        platform: PurchasePlatform.android,
        productId: 'com.mevora.app.boost',
        transactionId: 'GPA.1234',
        purchaseToken: 'token',
      ),
    ),
  });

  bool available;
  BoostProduct product;
  StorePurchaseEvent event;
  PurchaseException? buyError;
  final StreamController<StorePurchaseEvent> _events =
      StreamController<StorePurchaseEvent>.broadcast();
  StoreTransaction? completed;
  bool restored = false;

  @override
  Stream<StorePurchaseEvent> get purchaseEvents => _events.stream;

  @override
  Future<bool> isStoreAvailable() async => available;

  @override
  Future<BoostProduct> loadProduct(BoostProductConfig config) async {
    if (!available) {
      throw const PurchaseException(
        'Mağaza şu anda bu cihazda kullanılamıyor.',
        kind: PurchaseErrorKind.unavailable,
      );
    }
    return product;
  }

  @override
  Future<void> buy(BoostProduct product) async {
    final error = buyError;
    if (error != null) {
      throw error;
    }
    _events.add(event);
  }

  @override
  Future<void> complete(StoreTransaction transaction) async {
    completed = transaction;
  }

  @override
  Future<void> restore() async {
    restored = true;
  }

  Future<void> dispose() => _events.close();
}

class FakePurchaseRemoteDataSource implements PurchaseRemoteDataSource {
  FakePurchaseRemoteDataSource({this.active, this.verifyResult});

  Boost? active;
  Boost? verifyResult;
  PurchaseException? verifyError;
  int verifyCalls = 0;
  StoreTransaction? lastTransaction;

  @override
  Future<Boost?> loadActiveBoost(String userId) async => active;

  @override
  Future<Boost> verifyPurchase({
    required String userId,
    required StoreTransaction transaction,
  }) async {
    verifyCalls += 1;
    lastTransaction = transaction;
    final error = verifyError;
    if (error != null) {
      throw error;
    }
    return verifyResult!;
  }
}
