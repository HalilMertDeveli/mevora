import 'dart:async';

import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/features/boost/data/datasources/firebase_purchase_data_source.dart';
import 'package:mevora/features/boost/data/datasources/store_purchase_data_source.dart';
import 'package:mevora/features/boost/domain/config/boost_pack_catalog.dart';
import 'package:mevora/features/boost/domain/config/boost_product_config.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/features/boost/domain/entities/boost_credit_result.dart';
import 'package:mevora/features/boost/domain/entities/boost_history_entry.dart';
import 'package:mevora/features/boost/domain/entities/boost_pack.dart';
import 'package:mevora/features/boost/domain/entities/boost_product.dart';
import 'package:mevora/features/boost/domain/entities/boost_wallet.dart';
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
    this.products,
  });

  bool available;
  BoostProduct product;
  List<BoostProduct>? products;
  StorePurchaseEvent event;

  /// Reported by the store before [event], as another product's purchase on
  /// the shared store stream would be.
  List<StorePurchaseEvent> eventsBeforePurchase = const [];

  /// What the store redelivers when asked to restore.
  List<StorePurchaseEvent> restoreEvents = const [];

  /// Purchases the store still holds unconsumed from an earlier session.
  List<StoreTransaction> outstanding = const [];
  int outstandingQueries = 0;
  Object? outstandingError;

  /// Holds [buy] open, as the store sheet does while the member decides.
  Completer<void>? buyGate;
  PurchaseException? buyError;
  final StreamController<StorePurchaseEvent> _events =
      StreamController<StorePurchaseEvent>.broadcast();
  StoreTransaction? completed;
  final List<StoreTransaction> completions = <StoreTransaction>[];
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
  Future<List<BoostProduct>> loadProducts(BoostProductConfig config) async {
    if (!available) {
      throw const PurchaseException(
        'Mağaza şu anda bu cihazda kullanılamıyor.',
        kind: PurchaseErrorKind.unavailable,
      );
    }
    return products ?? [product];
  }

  @override
  Future<void> buy(BoostProduct product) async {
    final error = buyError;
    if (error != null) {
      throw error;
    }
    await buyGate?.future;
    eventsBeforePurchase.forEach(_events.add);
    _events.add(event);
  }

  /// Makes [complete] fail, as Play does for a purchase it no longer holds.
  PurchaseException? completeError;

  @override
  Future<void> complete(StoreTransaction transaction) async {
    final error = completeError;
    if (error != null) {
      throw error;
    }
    completed = transaction;
    completions.add(transaction);
  }

  @override
  Future<void> restore() async {
    restored = true;
    restoreEvents.forEach(_events.add);
  }

  @override
  Future<List<StoreTransaction>> outstandingPurchases() async {
    outstandingQueries += 1;
    final error = outstandingError;
    if (error != null) {
      throw error;
    }
    return outstanding;
  }

  Future<void> dispose() => _events.close();
}

class FakePurchaseRemoteDataSource implements PurchaseRemoteDataSource {
  FakePurchaseRemoteDataSource({
    this.active,
    this.verifyResult,
    this.activateResult,
    this.wallet = const BoostWallet(),
    List<BoostPack>? catalog,
    List<BoostHistoryEntry>? history,
  }) : catalog = catalog ?? BoostPackCatalog.storefrontPacks,
       history = history ?? const [];

  Boost? active;
  BoostCreditResult? verifyResult;
  Boost? activateResult;
  BoostWallet wallet;
  List<BoostPack> catalog;
  List<BoostHistoryEntry> history;
  PurchaseException? verifyError;

  /// How long the backend takes to answer a verification.
  Duration verifyDelay = Duration.zero;
  PurchaseException? activateError;
  int verifyCalls = 0;
  int activateCalls = 0;
  StoreTransaction? lastTransaction;

  @override
  Future<Boost?> loadActiveBoost(String userId) async => active;

  Boost? latestFinished;

  @override
  Future<Boost?> loadLatestFinishedBoost(String userId) async => latestFinished;

  @override
  Future<BoostCreditResult> verifyPurchase({
    required String userId,
    required StoreTransaction transaction,
  }) async {
    verifyCalls += 1;
    lastTransaction = transaction;
    if (verifyDelay > Duration.zero) {
      await Future<void>.delayed(verifyDelay);
    }
    final error = verifyError;
    if (error != null) {
      throw error;
    }
    return verifyResult!;
  }

  @override
  Future<Boost> activateBoost(String userId) async {
    activateCalls += 1;
    final error = activateError;
    if (error != null) {
      throw error;
    }
    return activateResult!;
  }

  @override
  Future<BoostWallet> loadWallet(String userId) async => wallet;

  @override
  Future<List<BoostHistoryEntry>> loadHistory(String userId) async => history;

  @override
  Future<List<BoostPack>> loadCatalog() async => catalog;
}
