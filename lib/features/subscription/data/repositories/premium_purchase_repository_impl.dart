import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/boost/domain/config/boost_product_config.dart';
import 'package:mevora/features/boost/domain/entities/store_transaction.dart';
import 'package:mevora/features/subscription/domain/config/premium_pack_catalog.dart';
import 'package:mevora/features/subscription/domain/repositories/premium_purchase_repository.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';

class PremiumPurchaseRepositoryImpl implements PremiumPurchaseRepository {
  PremiumPurchaseRepositoryImpl({
    required BackendCallable backend,
    required AuthUidSource uidSource,
    InAppPurchase? store,
  }) : _backend = backend,
       _uidSource = uidSource,
       _store = store ?? InAppPurchase.instance;

  final BackendCallable _backend;
  final AuthUidSource _uidSource;
  final InAppPurchase _store;

  @override
  Future<Result<List<String>>> loadStoreProductIds() async {
    try {
      final available = await _store.isAvailable();
      if (!available) {
        return const Err(UnexpectedFailure('store_unavailable'));
      }
      final response = await _store.queryProductDetails(
        PremiumPackCatalog.productIds.toSet(),
      );
      return Success(response.productDetails.map((e) => e.id).toList());
    } catch (error) {
      return Err(UnexpectedFailure('store_query_failed:$error'));
    }
  }

  @override
  Future<Result<PremiumPurchaseResult>> purchase({
    required String productId,
  }) async {
    final uid = _uidSource.currentUid;
    if (uid == null || uid.isEmpty) {
      return const Err(UnexpectedFailure('unauthenticated'));
    }
    if (!PremiumPackCatalog.productIds.contains(productId)) {
      return const Err(UnexpectedFailure('invalid_product'));
    }
    try {
      final available = await _store.isAvailable();
      if (!available) {
        return const Err(UnexpectedFailure('store_unavailable'));
      }
      final response = await _store.queryProductDetails({productId});
      if (response.productDetails.isEmpty) {
        return const Err(UnexpectedFailure('product_missing'));
      }
      final details = response.productDetails.first;
      final pending = _store.purchaseStream
          .map(_firstRelevant)
          .where((e) => e != null)
          .cast<PurchaseDetails>()
          .first;
      final started = await _store.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: details),
      );
      if (!started) {
        return const Err(UnexpectedFailure('purchase_failed'));
      }
      final purchase = await pending.timeout(const Duration(minutes: 5));
      if (purchase.status == PurchaseStatus.canceled) {
        return const Err(UnexpectedFailure('purchase_cancelled'));
      }
      if (purchase.status == PurchaseStatus.error) {
        return Err(
          UnexpectedFailure(purchase.error?.message ?? 'purchase_failed'),
        );
      }
      if (purchase.status == PurchaseStatus.pending) {
        return const Err(UnexpectedFailure('purchase_pending'));
      }
      final tx = _toTransaction(purchase);
      final verified = await _verify(tx);
      if (purchase.pendingCompletePurchase) {
        await _store.completePurchase(purchase);
      }
      return verified;
    } catch (error) {
      return Err(UnexpectedFailure('purchase_failed:$error'));
    }
  }

  @override
  Future<Result<List<PremiumPurchaseResult>>> restore() async {
    try {
      final available = await _store.isAvailable();
      if (!available) {
        return const Err(UnexpectedFailure('store_unavailable'));
      }
      final collected = <PurchaseDetails>[];
      final sub = _store.purchaseStream.listen(collected.addAll);
      await _store.restorePurchases();
      await Future<void>.delayed(const Duration(seconds: 2));
      await sub.cancel();
      final out = <PremiumPurchaseResult>[];
      for (final purchase in collected) {
        if (!PremiumPackCatalog.productIds.contains(purchase.productID)) {
          continue;
        }
        if (purchase.status != PurchaseStatus.purchased &&
            purchase.status != PurchaseStatus.restored) {
          continue;
        }
        final verified = await _verify(_toTransaction(purchase));
        verified.when(success: out.add, err: (_) {});
        if (purchase.pendingCompletePurchase) {
          await _store.completePurchase(purchase);
        }
      }
      return Success(out);
    } catch (error) {
      return Err(UnexpectedFailure('restore_failed:$error'));
    }
  }

  PurchaseDetails? _firstRelevant(List<PurchaseDetails> events) {
    for (final e in events) {
      if (e.status == PurchaseStatus.purchased ||
          e.status == PurchaseStatus.restored ||
          e.status == PurchaseStatus.canceled ||
          e.status == PurchaseStatus.error ||
          e.status == PurchaseStatus.pending) {
        return e;
      }
    }
    return null;
  }

  StoreTransaction _toTransaction(PurchaseDetails purchase) {
    final isIos = purchase.verificationData.source.contains('app_store') ||
        purchase.verificationData.source.contains('ios');
    return StoreTransaction(
      platform: isIos ? PurchasePlatform.ios : PurchasePlatform.android,
      productId: purchase.productID,
      transactionId: purchase.purchaseID ?? purchase.productID,
      purchaseToken:
          isIos ? null : purchase.verificationData.serverVerificationData,
      signedTransaction:
          isIos ? purchase.verificationData.serverVerificationData : null,
      receiptData:
          isIos ? purchase.verificationData.localVerificationData : null,
    );
  }

  Future<Result<PremiumPurchaseResult>> _verify(StoreTransaction tx) async {
    try {
      final data = await _backend.invoke('verifyPremiumPurchase', {
        'platform': tx.platform.name,
        'productId': tx.productId,
        'transactionId': tx.transactionId,
        if (tx.purchaseToken != null) 'purchaseToken': tx.purchaseToken,
        if (tx.signedTransaction != null)
          'signedTransaction': tx.signedTransaction,
        if (tx.receiptData != null) 'receiptData': tx.receiptData,
      });
      final sub = data['subscription'];
      var status = const PremiumStatus();
      if (sub is Map) {
        final expiresRaw = sub['expiresAt'];
        DateTime? expiresAt;
        if (expiresRaw is String) {
          expiresAt = DateTime.tryParse(expiresRaw);
        }
        status = PremiumStatus(
          isPremium: sub['isPremium'] == true,
          expiresAt: expiresAt,
        );
      }
      return Success(
        PremiumPurchaseResult(
          productId: tx.productId,
          alreadyProcessed: data['alreadyProcessed'] == true,
          status: status,
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      return Err(UnexpectedFailure(error.code));
    } catch (error) {
      return Err(UnexpectedFailure('verify_failed:$error'));
    }
  }
}
