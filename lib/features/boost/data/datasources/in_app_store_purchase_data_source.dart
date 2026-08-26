import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mevora/core/constants/app_strings.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/boost/data/datasources/store_purchase_data_source.dart';
import 'package:mevora/features/boost/data/services/apple_purchase_service.dart';
import 'package:mevora/features/boost/data/services/google_purchase_service.dart';
import 'package:mevora/features/boost/domain/config/boost_pack_catalog.dart';
import 'package:mevora/features/boost/domain/config/boost_product_config.dart';
import 'package:mevora/features/boost/domain/entities/boost_product.dart';
import 'package:mevora/features/boost/domain/entities/store_transaction.dart';

class InAppStorePurchaseDataSource implements StorePurchaseDataSource {
  InAppStorePurchaseDataSource({
    InAppPurchase? store,
    ApplePurchaseService? apple,
    GooglePurchaseService? google,
    AppLogger? logger,
    PurchasePlatform? platformOverride,
  }) : _store = store ?? InAppPurchase.instance,
       _apple = apple ?? ApplePurchaseService(store: store, logger: logger),
       _google = google ?? GooglePurchaseService(store: store, logger: logger),
       _logger = logger,
       _platformOverride = platformOverride {
    _subscription = _store.purchaseStream.listen(
      _onPurchases,
      onError: (Object error, StackTrace stackTrace) {
        _logger?.warning(
          'Store purchase stream error',
          error: error,
          stackTrace: stackTrace,
        );
        _events.add(
          const StorePurchaseEvent(
            status: StorePurchaseStatus.error,
            kind: PurchaseErrorKind.storeDown,
          ),
        );
      },
    );
  }

  final InAppPurchase _store;
  final ApplePurchaseService _apple;
  final GooglePurchaseService _google;
  final AppLogger? _logger;
  final PurchasePlatform? _platformOverride;
  final Map<String, PurchaseDetails> _open = {};
  final StreamController<StorePurchaseEvent> _events =
      StreamController<StorePurchaseEvent>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  PurchasePlatform get _platform {
    if (_platformOverride != null) {
      return _platformOverride;
    }
    return defaultTargetPlatform == TargetPlatform.iOS
        ? PurchasePlatform.ios
        : PurchasePlatform.android;
  }

  @override
  Stream<StorePurchaseEvent> get purchaseEvents => _events.stream;

  @override
  Future<bool> isStoreAvailable() async {
    try {
      return await _store.isAvailable();
    } on Object catch (error, stackTrace) {
      _logger?.warning(
        'Store availability check failed',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  @override
  Future<BoostProduct> loadProduct(BoostProductConfig config) async {
    final available = await isStoreAvailable();
    if (!available) {
      throw const PurchaseException(
        AppStrings.boostStoreUnavailable,
        kind: PurchaseErrorKind.unavailable,
      );
    }
    final productId = config.productIdFor(_platform);
    try {
      final response = await _store.queryProductDetails({productId});
      if (response.error != null && response.productDetails.isEmpty) {
        throw const PurchaseException(
          AppStrings.boostStoreDown,
          kind: PurchaseErrorKind.storeDown,
        );
      }
      if (response.productDetails.isEmpty) {
        throw const PurchaseException(
          AppStrings.boostStoreUnavailable,
          kind: PurchaseErrorKind.unavailable,
        );
      }
      final details = response.productDetails.first;
      return BoostProduct(
        productId: details.id,
        title: details.title,
        description: details.description,
        localizedPrice: details.price,
        currency: details.currencyCode,
        available: true,
        duration: config.duration,
        displayOrder: config.displayOrder,
        boostCount: BoostPackCatalog.boostCountFor(details.id),
        featured: BoostPackCatalog.packFor(details.id)?.featured ?? false,
      );
    } on PurchaseException {
      rethrow;
    } on Object catch (error, stackTrace) {
      _logger?.warning(
        'Store product query failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw const PurchaseException(
        AppStrings.boostStoreDown,
        kind: PurchaseErrorKind.storeDown,
      );
    }
  }

  @override
  Future<List<BoostProduct>> loadProducts(BoostProductConfig config) async {
    final available = await isStoreAvailable();
    if (!available) {
      throw const PurchaseException(
        AppStrings.boostStoreUnavailable,
        kind: PurchaseErrorKind.unavailable,
      );
    }
    try {
      final response = await _store.queryProductDetails(
        BoostPackCatalog.storefrontSkus,
      );
      if (response.error != null && response.productDetails.isEmpty) {
        throw const PurchaseException(
          AppStrings.boostStoreDown,
          kind: PurchaseErrorKind.storeDown,
        );
      }
      return response.productDetails.map((details) {
        final pack = BoostPackCatalog.packFor(details.id);
        return BoostProduct(
          productId: details.id,
          title: details.title,
          description: details.description,
          localizedPrice: details.price,
          currency: details.currencyCode,
          available: true,
          duration: pack?.duration ?? config.duration,
          displayOrder: pack?.displayOrder ?? config.displayOrder,
          boostCount: pack?.boostCount ?? 0,
          featured: pack?.featured ?? false,
        );
      }).toList();
    } on PurchaseException {
      rethrow;
    } on Object catch (error, stackTrace) {
      _logger?.warning(
        'Store product query failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw const PurchaseException(
        AppStrings.boostStoreDown,
        kind: PurchaseErrorKind.storeDown,
      );
    }
  }

  @override
  Future<void> buy(BoostProduct product) async {
    final available = await isStoreAvailable();
    if (!available) {
      throw const PurchaseException(
        AppStrings.boostStoreUnavailable,
        kind: PurchaseErrorKind.unavailable,
      );
    }
    try {
      final response = await _store.queryProductDetails({product.productId});
      if (response.productDetails.isEmpty) {
        throw const PurchaseException(
          AppStrings.boostStoreUnavailable,
          kind: PurchaseErrorKind.unavailable,
        );
      }
      final param = PurchaseParam(
        productDetails: response.productDetails.first,
      );
      final started = await _store.buyConsumable(
        purchaseParam: param,
        autoConsume: false,
      );
      if (!started) {
        throw const PurchaseException(
          AppStrings.boostPurchaseFailed,
          kind: PurchaseErrorKind.failed,
        );
      }
    } on PurchaseException {
      rethrow;
    } on Object catch (error, stackTrace) {
      _logger?.warning(
        'Store buy failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw const PurchaseException(
        AppStrings.boostPurchaseFailed,
        kind: PurchaseErrorKind.failed,
      );
    }
  }

  @override
  Future<void> complete(StoreTransaction transaction) async {
    final details = _open.remove(transaction.transactionId);
    if (details == null) {
      return;
    }
    if (_platform == PurchasePlatform.ios) {
      await _apple.finish(details);
      return;
    }
    await _google.consume(details);
    if (details.pendingCompletePurchase) {
      await _store.completePurchase(details);
    }
  }

  @override
  Future<void> restore() async {
    if (_platform == PurchasePlatform.ios) {
      await _apple.restoreConsumables();
      return;
    }
    await _google.restoreUnconsumed();
  }

  void _onPurchases(List<PurchaseDetails> purchases) {
    for (final details in purchases) {
      final transactionId = details.purchaseID ?? details.verificationData.source;
      if (transactionId.isEmpty) {
        _events.add(
          const StorePurchaseEvent(
            status: StorePurchaseStatus.error,
            kind: PurchaseErrorKind.failed,
          ),
        );
        continue;
      }
      _open[transactionId] = details;
      final transaction = StoreTransaction(
        platform: _platform,
        productId: details.productID,
        transactionId: transactionId,
        purchaseToken: _platform == PurchasePlatform.android
            ? details.verificationData.serverVerificationData
            : null,
        signedTransaction: _platform == PurchasePlatform.ios
            ? details.verificationData.serverVerificationData
            : null,
        receiptData: _platform == PurchasePlatform.ios
            ? details.verificationData.serverVerificationData
            : null,
        localVerificationData: details.verificationData.localVerificationData,
      );
      switch (details.status) {
        case PurchaseStatus.pending:
          _events.add(
            StorePurchaseEvent(
              status: StorePurchaseStatus.pending,
              transaction: transaction,
            ),
          );
        case PurchaseStatus.purchased:
          _events.add(
            StorePurchaseEvent(
              status: StorePurchaseStatus.purchased,
              transaction: transaction,
            ),
          );
        case PurchaseStatus.restored:
          _events.add(
            StorePurchaseEvent(
              status: StorePurchaseStatus.restored,
              transaction: transaction,
            ),
          );
        case PurchaseStatus.canceled:
          _events.add(
            StorePurchaseEvent(
              status: StorePurchaseStatus.cancelled,
              transaction: transaction,
              kind: PurchaseErrorKind.cancelled,
            ),
          );
        case PurchaseStatus.error:
          _events.add(
            StorePurchaseEvent(
              status: StorePurchaseStatus.error,
              transaction: transaction,
              kind: PurchaseErrorKind.failed,
            ),
          );
      }
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _events.close();
  }
}
