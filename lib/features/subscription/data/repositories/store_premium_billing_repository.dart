import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/subscription/domain/config/premium_product_config.dart';
import 'package:mevora/features/subscription/domain/entities/premium_plan.dart';
import 'package:mevora/features/subscription/domain/repositories/premium_billing_repository.dart';

/// Play Billing / StoreKit in front, the `verifyPremiumPurchase` callable
/// behind.
///
/// The one rule this class exists to enforce: a store saying "purchased" is
/// not Premium. Every path — first purchase and restore alike — carries the
/// token to the backend and returns the backend's answer. Nothing here writes
/// entitlement, and there is no branch that could.
class StorePremiumBillingRepository implements PremiumBillingRepository {
  StorePremiumBillingRepository({
    required BackendCallable backend,
    PremiumProductConfig config = const PremiumProductConfig(),
    InAppPurchase? store,
    AppLogger? logger,
    PremiumPlatform? platformOverride,
  }) : _backend = backend,
       _config = config,
       _store = store ?? InAppPurchase.instance,
       _logger = logger,
       _platformOverride = platformOverride {
    _subscription = _store.purchaseStream.listen(
      _onPurchases,
      onError: (Object error, StackTrace stackTrace) {
        _logger?.warning(
          'Premium purchase stream error',
          error: error,
          stackTrace: stackTrace,
        );
        _failPending(
          const PremiumBillingException(PremiumPurchaseFailure.transient),
        );
      },
    );
  }

  static const String _callable = 'verifyPremiumPurchase';

  final BackendCallable _backend;
  final PremiumProductConfig _config;
  final InAppPurchase _store;
  final AppLogger? _logger;
  final PremiumPlatform? _platformOverride;

  StreamSubscription<List<PurchaseDetails>>? _subscription;

  /// The buy currently waiting on the store sheet. Only one at a time: the
  /// store shows one sheet, so a second concurrent buy would have nothing
  /// coherent to wait for.
  Completer<PremiumVerificationResult>? _pending;
  String? _pendingProductId;

  /// Restored purchases arrive as a burst with no request to correlate them
  /// to, so they are collected here for [restore] to drain.
  final List<PurchaseDetails> _restored = <PurchaseDetails>[];
  Completer<void>? _restoreDrain;

  PremiumPlatform get _platform {
    if (_platformOverride != null) {
      return _platformOverride;
    }
    return defaultTargetPlatform == TargetPlatform.iOS
        ? PremiumPlatform.ios
        : PremiumPlatform.android;
  }

  @override
  Future<bool> isStoreAvailable() async {
    try {
      return await _store.isAvailable();
    } on Object catch (error, stackTrace) {
      _logger?.warning(
        'Premium store availability check failed',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  @override
  Future<List<PremiumPlan>> loadPlans() async {
    final ids = _config.queryIdsFor(_platform);
    if (ids.isEmpty) {
      // Nothing configured for this build. Say so by returning nothing rather
      // than showing a plan that cannot be bought.
      return const [];
    }
    if (!await isStoreAvailable()) {
      throw const PremiumBillingException(
        PremiumPurchaseFailure.storeUnavailable,
      );
    }
    try {
      final response = await _store.queryProductDetails(ids);
      return response.productDetails.map(_toPlan).toList(growable: false);
    } on Object catch (error, stackTrace) {
      _logger?.warning(
        'Premium product query failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw const PremiumBillingException(
        PremiumPurchaseFailure.productsUnavailable,
      );
    }
  }

  @override
  Future<PremiumVerificationResult> purchase(PremiumPlan plan) async {
    if (!_config.allows(_platform, plan.productId)) {
      // Refusing here keeps an unrelated SKU from ever reaching the verifier.
      throw const PremiumBillingException(
        PremiumPurchaseFailure.productsUnavailable,
      );
    }
    if (_pending != null) {
      throw const PremiumBillingException(PremiumPurchaseFailure.unknown);
    }
    if (!await isStoreAvailable()) {
      throw const PremiumBillingException(
        PremiumPurchaseFailure.storeUnavailable,
      );
    }

    final ProductDetailsResponse response;
    try {
      response = await _store.queryProductDetails({plan.productId});
    } on Object catch (error, stackTrace) {
      _logger?.warning(
        'Premium product lookup failed before buy',
        error: error,
        stackTrace: stackTrace,
      );
      throw const PremiumBillingException(
        PremiumPurchaseFailure.productsUnavailable,
      );
    }
    if (response.productDetails.isEmpty) {
      throw const PremiumBillingException(
        PremiumPurchaseFailure.productsUnavailable,
      );
    }

    final completer = Completer<PremiumVerificationResult>();
    _pending = completer;
    _pendingProductId = plan.productId;
    try {
      // Subscriptions are non-consumable to the plugin on both stores, even
      // though they expire. buyConsumable here would be wrong and, on Android,
      // would consume the subscription.
      final started = await _store.buyNonConsumable(
        purchaseParam: PurchaseParam(
          productDetails: response.productDetails.first,
        ),
      );
      if (!started) {
        throw const PremiumBillingException(PremiumPurchaseFailure.unknown);
      }
    } on Object catch (error, stackTrace) {
      _pending = null;
      _pendingProductId = null;
      if (error is PremiumBillingException) {
        rethrow;
      }
      _logger?.warning(
        'Premium buy failed to start',
        error: error,
        stackTrace: stackTrace,
      );
      throw const PremiumBillingException(PremiumPurchaseFailure.unknown);
    }
    return completer.future;
  }

  @override
  Future<PremiumVerificationResult> restore() async {
    if (!await isStoreAvailable()) {
      throw const PremiumBillingException(
        PremiumPurchaseFailure.storeUnavailable,
      );
    }
    _restored.clear();
    final drain = Completer<void>();
    _restoreDrain = drain;
    try {
      await _store.restorePurchases();
    } on Object catch (error, stackTrace) {
      _restoreDrain = null;
      _logger?.warning(
        'Premium restore failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw const PremiumBillingException(PremiumPurchaseFailure.transient);
    }

    // The stream completes the drain as soon as a restored batch lands. The
    // timeout is the "store has nothing for this account" case, which the
    // plugin does not report explicitly.
    await drain.future.timeout(const Duration(seconds: 12), onTimeout: () {});
    _restoreDrain = null;

    final pending = List<PurchaseDetails>.from(_restored);
    _restored.clear();
    if (pending.isEmpty) {
      return const PremiumVerificationResult.rejected('nothing_to_restore');
    }

    // Several old subscriptions can come back. Any one of them granting
    // Premium is enough, so stop at the first that does.
    PremiumVerificationResult last = const PremiumVerificationResult.rejected(
      'nothing_to_restore',
    );
    for (final details in pending) {
      final result = await _verifyAndFinish(details);
      last = result;
      if (result.isPremium) {
        return result;
      }
    }
    return last;
  }

  void _onPurchases(List<PurchaseDetails> purchases) {
    for (final details in purchases) {
      unawaited(_handle(details));
    }
  }

  Future<void> _handle(PurchaseDetails details) async {
    switch (details.status) {
      case PurchaseStatus.pending:
        // Deferred payment. Nothing to verify yet and nothing to unlock; the
        // store will emit again when it resolves.
        return;
      case PurchaseStatus.canceled:
        _failPending(
          const PremiumBillingException(PremiumPurchaseFailure.cancelled),
        );
        return;
      case PurchaseStatus.error:
        _logger?.warning(
          'Premium purchase reported an error: ${details.error?.message}',
        );
        await _finish(details);
        _failPending(
          const PremiumBillingException(PremiumPurchaseFailure.unknown),
        );
        return;
      case PurchaseStatus.restored:
        _restored.add(details);
        final drain = _restoreDrain;
        if (drain != null && !drain.isCompleted) {
          drain.complete();
        }
        return;
      case PurchaseStatus.purchased:
        try {
          final result = await _verifyAndFinish(details);
          _completePending(details, result);
        } on PremiumBillingException catch (error) {
          _failPending(error);
        }
        return;
    }
  }

  /// Verify with the backend first, finish with the store second.
  ///
  /// Order matters: finishing before verification would tell the store the
  /// purchase is handled while the entitlement might never have been written,
  /// and the token would stop being redelivered.
  Future<PremiumVerificationResult> _verifyAndFinish(
    PurchaseDetails details,
  ) async {
    final token = _evidenceFor(details);
    if (token.isEmpty) {
      await _finish(details);
      return const PremiumVerificationResult.rejected('missing_evidence');
    }
    final Map<String, dynamic> response;
    try {
      response = await _backend.invoke(_callable, <String, dynamic>{
        'platform': _platform.name,
        'purchaseToken': token,
        'productId': details.productID,
      });
    } on Object catch (error, stackTrace) {
      _logger?.warning(
        'Premium verification call failed',
        error: error,
        stackTrace: stackTrace,
      );
      // Leave the purchase unfinished so the store redelivers it and a later
      // launch can try again.
      throw const PremiumBillingException(PremiumPurchaseFailure.transient);
    }
    final result = PremiumVerificationResult(
      ok: response['ok'] == true,
      isPremium: response['isPremium'] == true,
      reason: response['reason'] as String?,
    );
    // Only stop the store redelivering once the backend has taken
    // responsibility for the token. A rejected-but-answered verification
    // counts: replaying it would just be rejected again.
    await _finish(details);
    return result;
  }

  /// What the backend needs in order to go and ask the store itself.
  ///
  /// The two stores identify a subscription differently, and sending the wrong
  /// one would be a lookup that always fails rather than a security hole:
  /// Google verifies a purchase token, Apple looks up a transaction id. The
  /// iOS receipt in `serverVerificationData` is not an identifier the
  /// subscription-status endpoint accepts, so the transaction id is sent.
  String _evidenceFor(PurchaseDetails details) {
    return switch (_platform) {
      PremiumPlatform.android =>
        details.verificationData.serverVerificationData,
      PremiumPlatform.ios => details.purchaseID ?? '',
    };
  }

  Future<void> _finish(PurchaseDetails details) async {
    if (!details.pendingCompletePurchase) {
      return;
    }
    try {
      await _store.completePurchase(details);
    } on Object catch (error, stackTrace) {
      _logger?.warning(
        'Premium completePurchase failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _completePending(
    PurchaseDetails details,
    PremiumVerificationResult result,
  ) {
    final pending = _pending;
    if (pending == null || pending.isCompleted) {
      return;
    }
    if (_pendingProductId != null && details.productID != _pendingProductId) {
      return;
    }
    _pending = null;
    _pendingProductId = null;
    pending.complete(result);
  }

  void _failPending(PremiumBillingException error) {
    final pending = _pending;
    if (pending == null || pending.isCompleted) {
      return;
    }
    _pending = null;
    _pendingProductId = null;
    pending.completeError(error);
  }

  PremiumPlan _toPlan(ProductDetails details) {
    return PremiumPlan(
      productId: details.id,
      title: details.title,
      description: details.description,
      // Store-formatted and already localised. Never rebuilt from rawPrice.
      formattedPrice: details.price,
      period: _periodOf(details),
    );
  }

  /// Best-effort read of the billing period. The plugin does not expose a
  /// structured period on every platform, so an unrecognised product stays
  /// [PremiumPlanPeriod.unknown] and the UI shows the store's own title.
  PremiumPlanPeriod _periodOf(ProductDetails details) {
    final haystack = '${details.id} ${details.title}'.toLowerCase();
    if (haystack.contains('year') || haystack.contains('annual')) {
      return PremiumPlanPeriod.yearly;
    }
    if (haystack.contains('month')) {
      return PremiumPlanPeriod.monthly;
    }
    return PremiumPlanPeriod.unknown;
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
