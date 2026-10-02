import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
// Base plans, offer tokens and the Play purchase parameter exist only on the
// Android implementation's types. `in_app_purchase` depends on that package
// but re-exports none of it.
// ignore: depend_on_referenced_packages
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
// ignore: depend_on_referenced_packages
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
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
    AuthUidSource? uidSource,
    Future<List<PurchaseDetails>> Function()? outstandingPurchases,
  }) : _backend = backend,
       _config = config,
       _store = store ?? InAppPurchase.instance,
       _logger = logger,
       _platformOverride = platformOverride,
       _uidSource = uidSource,
       _outstandingPurchases = outstandingPurchases {
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
    // Every launch with an account, and every sign-in: the two moments a
    // purchase from an earlier session can first be verified for someone.
    String? reverifiedFor;
    _uidSubscription = uidSource?.watchUid().listen((uid) {
      if (uid == null || uid == reverifiedFor) {
        reverifiedFor = uid;
        return;
      }
      reverifiedFor = uid;
      unawaited(reverifyOutstandingPurchases());
    });
  }

  static const String _callable = 'verifyPremiumPurchase';

  /// Refusals that mean "nothing could be checked", from a backend deployed
  /// before it started throwing them. Never an answer to act on.
  static const Set<String> _unverifiedReasons = <String>{
    'unavailable',
    'not_configured',
    'transient',
  };

  final BackendCallable _backend;
  final PremiumProductConfig _config;
  final InAppPurchase _store;
  final AppLogger? _logger;
  final PremiumPlatform? _platformOverride;
  final AuthUidSource? _uidSource;
  final Future<List<PurchaseDetails>> Function()? _outstandingPurchases;

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  StreamSubscription<String?>? _uidSubscription;
  bool _reverifying = false;

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

  /// What a purchase is stamped with so the backend can tell whose it is
  /// (Play's `obfuscatedAccountId`). A hash, because Play refuses anything
  /// personal there, and 64 characters, which is Play's limit.
  ///
  /// Must match `premiumAccountId` in `verifyPremiumPurchase.ts`.
  static String accountIdFor(String uid) {
    return sha256.convert(utf8.encode(uid)).toString();
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
      return _offersFrom(
        response.productDetails,
      ).map((offer) => offer.plan).toList(growable: false);
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
    // One Play subscription comes back as a product detail per base plan, all
    // with the same id. The one bought has to be the one that was tapped, and
    // if the store no longer offers it there is no acceptable substitute.
    final offer = _offersFrom(
      response.productDetails,
    ).where((offer) => offer.plan.planKey == plan.planKey).firstOrNull;
    if (offer == null) {
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
        purchaseParam: _purchaseParamFor(offer.details),
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

  PurchaseParam _purchaseParamFor(ProductDetails details) {
    if (details is! GooglePlayProductDetails) {
      return PurchaseParam(productDetails: details);
    }
    final uid = _uidSource?.currentUid;
    return GooglePlayPurchaseParam(
      productDetails: details,
      // Named explicitly: this token is what selects the base plan.
      offerToken: details.offerToken,
      applicationUserName: uid == null ? null : accountIdFor(uid),
    );
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

  /// Verifies Premium purchases the store holds that were never acknowledged:
  /// bought while the backend could not be reached, or paid for after the app
  /// had gone (a pending payment that settled later).
  ///
  /// Play refunds a subscription nobody acknowledges within three days, and
  /// unlike StoreKit it does not hand such purchases back on its own, so
  /// without this they would wait for the member to think of "restore". Runs
  /// when an account is available; safe to call at any time.
  ///
  /// Asks Play directly rather than through [InAppPurchase.restorePurchases],
  /// which would replay every purchase to every listener of the shared stream.
  Future<void> reverifyOutstandingPurchases() async {
    if (_platform != PremiumPlatform.android || _reverifying) {
      // StoreKit redelivers unfinished transactions through the purchase
      // stream by itself, where they are verified like any other.
      return;
    }
    if (_config.forPlatform(_platform).isEmpty) {
      return;
    }
    _reverifying = true;
    try {
      if (!await isStoreAvailable()) {
        return;
      }
      final purchases = await (_outstandingPurchases ?? _queryPlayPurchases)();
      for (final details in purchases) {
        // Still unpaid, already accounted for, or not Premium's to touch.
        if (details.status != PurchaseStatus.purchased ||
            !details.pendingCompletePurchase ||
            !_isPremiumProduct(details)) {
          continue;
        }
        try {
          await _verifyAndFinish(details);
        } on PremiumBillingException {
          // Still unreachable. It stays unacknowledged for the next attempt.
        }
      }
    } on Object catch (error, stackTrace) {
      _logger?.warning(
        'Premium outstanding purchase check failed',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _reverifying = false;
    }
  }

  Future<List<PurchaseDetails>> _queryPlayPurchases() async {
    final addition = _store
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final response = await addition.queryPastPurchases();
    return response.pastPurchases;
  }

  void _onPurchases(List<PurchaseDetails> purchases) {
    for (final details in purchases) {
      unawaited(_handle(details));
    }
  }

  /// The purchase stream is shared by everything the app sells. Anything that
  /// is not a configured Premium product belongs to another listener — Boost
  /// packs are consumables with their own verifier — and must never be
  /// verified as Premium, let alone completed, from here.
  bool _isPremiumProduct(PurchaseDetails details) {
    return _config.allows(_platform, details.productID);
  }

  Future<void> _handle(PurchaseDetails details) async {
    if (details.productID.isEmpty) {
      // Play reports a sheet that closed without a purchase as a detail with
      // no product on it. It can only end the buy that is waiting; there is
      // nothing to verify or finish.
      if (details.status == PurchaseStatus.canceled) {
        _failPending(
          const PremiumBillingException(PremiumPurchaseFailure.cancelled),
        );
      } else if (details.status == PurchaseStatus.error) {
        _logger?.warning(
          'Premium purchase reported an error: ${details.error?.message}',
        );
        _failPending(
          const PremiumBillingException(PremiumPurchaseFailure.unknown),
        );
      }
      return;
    }
    if (details.status == PurchaseStatus.restored) {
      if (_isPremiumProduct(details)) {
        _restored.add(details);
      }
      // Any restored batch means the store has answered, whatever was in it.
      final drain = _restoreDrain;
      if (drain != null && !drain.isCompleted) {
        drain.complete();
      }
      return;
    }
    if (!_isPremiumProduct(details)) {
      return;
    }
    switch (details.status) {
      case PurchaseStatus.pending:
        // Deferred payment (cash, bank transfer). Nothing has been paid, so
        // there is nothing to verify or unlock — but the buy is over as far
        // as the sheet goes, and leaving it open would spin forever and block
        // the next one. The store emits again when the payment settles, and
        // [reverifyOutstandingPurchases] covers it settling while the app is
        // closed.
        _completePending(details, const PremiumVerificationResult.pending());
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
        // A purchase that failed took no payment; finishing it only clears it
        // from the store's queue.
        await _finish(details);
        _failPending(
          const PremiumBillingException(PremiumPurchaseFailure.unknown),
        );
        return;
      case PurchaseStatus.restored:
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

  /// Verify with the backend first, finish with the store second — and only
  /// when the backend's answer accounts for the purchase.
  ///
  /// Finishing acknowledges the purchase: it tells the store the member got
  /// what they paid for, and stops Play refunding it after three days. So it
  /// may only follow an answer that says the entitlement exists:
  ///
  /// - `ok` — the backend wrote the entitlement state for this purchase, or
  ///   already held it. That includes a subscription that has since expired:
  ///   its state is recorded and there is nothing further to verify.
  /// - `owned_by_other` — the entitlement exists, under the account that
  ///   claimed this purchase first. Nothing is left to verify and no payment
  ///   is left unaccounted for.
  ///
  /// Everything else leaves the purchase unfinished, to be presented again by
  /// restore or [reverifyOutstandingPurchases]:
  ///
  /// - the call failed, or the backend could not check (store unreachable,
  ///   nothing configured) — nothing was decided;
  /// - `unknown_product`, `unknown_base_plan`, `package_mismatch` — only
  ///   products this build is configured to sell as Premium reach the
  ///   backend, so these mean the app and the backend disagree about what
  ///   Premium is. That is a configuration fault on a purchase that was really
  ///   paid for, and acknowledging it would keep the money for nothing;
  /// - `invalid` — the store did not know the token under the package the
  ///   backend asked with, which a wrongly configured package also produces;
  /// - `account_mismatch` — bought by a different Mevora account, which can
  ///   still claim it;
  /// - anything this build does not recognise.
  ///
  /// Not finishing is the safe direction: the worst case is one more
  /// verification on a later launch and, on Play, an automatic refund.
  Future<PremiumVerificationResult> _verifyAndFinish(
    PurchaseDetails details,
  ) async {
    final token = _evidenceFor(details);
    if (token.isEmpty) {
      // Nothing to verify with, so nothing the backend can have recorded.
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
      // Leave the purchase unfinished so it is presented again.
      throw const PremiumBillingException(PremiumPurchaseFailure.transient);
    }
    final result = PremiumVerificationResult(
      ok: response['ok'] == true,
      isPremium: response['isPremium'] == true,
      reason: response['reason'] as String?,
    );
    if (!result.ok && _unverifiedReasons.contains(result.reason)) {
      throw const PremiumBillingException(PremiumPurchaseFailure.transient);
    }
    if (result.ok || result.reason == 'owned_by_other') {
      await _finish(details);
    }
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

  /// The plans the store offers that this build is configured to sell, each
  /// paired with the store object that buys exactly that plan.
  ///
  /// Play describes one subscription as a product detail per offer — one for
  /// each base plan, plus one for each promotional offer on a base plan — all
  /// sharing the product id. A plan here is a base plan. Where a base plan
  /// also has promotional offers, the base plan's own entry is the one kept:
  /// its price is the price shown and the price charged.
  List<_PremiumOffer> _offersFrom(List<ProductDetails> products) {
    final offers = <String, _PremiumOffer>{};
    final atBasePrice = <String>{};
    for (final details in products) {
      final offer = _playOfferOf(details);
      if (!_config.allowsPlan(_platform, details.id, offer?.basePlanId)) {
        continue;
      }
      final plan = _toPlan(details, offer);
      final isBasePrice = offer == null || offer.offerId == null;
      if (!offers.containsKey(plan.planKey) ||
          (isBasePrice && !atBasePrice.contains(plan.planKey))) {
        offers[plan.planKey] = _PremiumOffer(plan, details);
      }
      if (isBasePrice) {
        atBasePrice.add(plan.planKey);
      }
    }
    return offers.values.toList(growable: false);
  }

  /// The Play offer a product detail stands for, or null off Play and for a
  /// product without base plans.
  SubscriptionOfferDetailsWrapper? _playOfferOf(ProductDetails details) {
    if (details is! GooglePlayProductDetails) {
      return null;
    }
    final index = details.subscriptionIndex;
    final offers = details.productDetails.subscriptionOfferDetails;
    if (index == null || offers == null || index >= offers.length) {
      return null;
    }
    return offers[index];
  }

  PremiumPlan _toPlan(
    ProductDetails details,
    SubscriptionOfferDetailsWrapper? offer,
  ) {
    return PremiumPlan(
      productId: details.id,
      basePlanId: offer?.basePlanId,
      title: details.title,
      description: details.description,
      // Store-formatted and already localised. Never rebuilt from rawPrice.
      formattedPrice: details.price,
      period: _periodOf(details, offer),
    );
  }

  /// Play states the billing period outright; elsewhere it is a best-effort
  /// read of the names, and an unrecognised product stays
  /// [PremiumPlanPeriod.unknown] so the UI shows the store's own title.
  PremiumPlanPeriod _periodOf(
    ProductDetails details,
    SubscriptionOfferDetailsWrapper? offer,
  ) {
    // The last phase is the one that recurs, after any introductory ones.
    final phases = offer?.pricingPhases ?? const <PricingPhaseWrapper>[];
    switch (phases.isEmpty ? null : phases.last.billingPeriod) {
      case 'P1Y':
        return PremiumPlanPeriod.yearly;
      case 'P1M':
        return PremiumPlanPeriod.monthly;
    }
    final haystack = '${details.id} ${offer?.basePlanId ?? ''} ${details.title}'
        .toLowerCase();
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
    await _uidSubscription?.cancel();
    _uidSubscription = null;
  }
}

/// A plan as shown, and the store's handle for buying exactly that plan.
class _PremiumOffer {
  const _PremiumOffer(this.plan, this.details);

  final PremiumPlan plan;
  final ProductDetails details;
}
