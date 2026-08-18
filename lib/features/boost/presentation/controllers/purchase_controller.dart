import 'package:flutter/foundation.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/analytics/noop_analytics_provider.dart';
import 'package:mevora/core/constants/app_strings.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/failure_messages.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/features/boost/domain/entities/boost_product.dart';
import 'package:mevora/features/boost/domain/entities/purchase_flow_state.dart';
import 'package:mevora/features/boost/domain/usecases/get_active_boost.dart';
import 'package:mevora/features/boost/domain/usecases/get_boost_product.dart';
import 'package:mevora/features/boost/domain/usecases/purchase_boost.dart';
import 'package:mevora/features/boost/domain/usecases/verify_boost_purchase.dart';
import 'package:mevora/features/boost/domain/repositories/purchase_repository.dart';

class PurchaseViewState {
  const PurchaseViewState({
    this.status = PurchaseUiStatus.initial,
    this.product,
    this.activeBoost,
    this.message,
    this.errorKind,
  });

  final PurchaseUiStatus status;
  final BoostProduct? product;
  final Boost? activeBoost;
  final String? message;
  final PurchaseErrorKind? errorKind;

  bool get hasActiveBoost => activeBoost != null;

  PurchaseViewState copyWith({
    PurchaseUiStatus? status,
    BoostProduct? product,
    Boost? activeBoost,
    bool clearBoost = false,
    String? message,
    bool clearMessage = false,
    PurchaseErrorKind? errorKind,
    bool clearErrorKind = false,
  }) {
    return PurchaseViewState(
      status: status ?? this.status,
      product: product ?? this.product,
      activeBoost: clearBoost ? null : (activeBoost ?? this.activeBoost),
      message: clearMessage ? null : (message ?? this.message),
      errorKind: clearErrorKind ? null : (errorKind ?? this.errorKind),
    );
  }
}

/// Owns Boost purchase UI state. Does not import StoreKit, Play, or Firebase.
class PurchaseController extends ChangeNotifier {
  PurchaseController({
    required this.userId,
    required GetBoostProduct getBoostProduct,
    required PurchaseBoost purchaseBoost,
    required VerifyBoostPurchase verifyBoostPurchase,
    required GetActiveBoost getActiveBoost,
    required PurchaseRepository repository,
    AnalyticsProvider? analytics,
  }) : _getBoostProduct = getBoostProduct,
       _purchaseBoost = purchaseBoost,
       _verifyBoostPurchase = verifyBoostPurchase,
       _getActiveBoost = getActiveBoost,
       _repository = repository,
       _analytics = analytics ?? const NoopAnalyticsProvider();

  final String userId;
  final GetBoostProduct _getBoostProduct;
  final PurchaseBoost _purchaseBoost;
  final VerifyBoostPurchase _verifyBoostPurchase;
  final GetActiveBoost _getActiveBoost;
  final PurchaseRepository _repository;
  final AnalyticsProvider _analytics;

  PurchaseViewState state = const PurchaseViewState();

  Future<void> load() async {
    state = state.copyWith(
      status: PurchaseUiStatus.loading,
      clearMessage: true,
      clearErrorKind: true,
    );
    notifyListeners();
    await _analytics.logEvent(AnalyticsEvents.boostViewed);

    final active = await _getActiveBoost(userId);
    final product = await _getBoostProduct();

    Boost? boost;
    switch (active) {
      case Success(:final value):
        boost = value;
      case Err():
        break;
    }

    if (boost != null) {
      state = state.copyWith(
        status: PurchaseUiStatus.productLoaded,
        activeBoost: boost,
        product: product.valueOrNull,
        message: AppStrings.boostAlreadyActive,
        errorKind: PurchaseErrorKind.alreadyActive,
      );
      notifyListeners();
      return;
    }

    switch (product) {
      case Success(:final value):
        state = state.copyWith(
          status: value.available
              ? PurchaseUiStatus.productLoaded
              : PurchaseUiStatus.unavailable,
          product: value,
          clearBoost: true,
          clearMessage: true,
          message: value.available ? null : AppStrings.boostStoreUnavailable,
          errorKind: value.available ? null : PurchaseErrorKind.unavailable,
          clearErrorKind: value.available,
        );
      case Err(:final failure):
        state = state.copyWith(
          status: _statusFor(failure),
          message: FailureMessages.of(failure),
          errorKind: failure is PurchaseFailure ? failure.kind : null,
          clearBoost: true,
        );
    }
    notifyListeners();
  }

  Future<void> purchase() async {
    final product = state.product;
    if (product == null || state.hasActiveBoost) {
      if (state.hasActiveBoost) {
        state = state.copyWith(
          status: PurchaseUiStatus.failed,
          message: AppStrings.boostAlreadyActive,
          errorKind: PurchaseErrorKind.alreadyActive,
        );
        notifyListeners();
      }
      return;
    }

    state = state.copyWith(
      status: PurchaseUiStatus.purchasing,
      message: AppStrings.boostPurchasing,
    );
    notifyListeners();
    await _analytics.logEvent(AnalyticsEvents.boostPurchaseStarted);

    final purchased = await _purchaseBoost(product);
    switch (purchased) {
      case Err(:final failure):
        await _fail(failure);
        return;
      case Success(:final value):
        state = state.copyWith(
          status: PurchaseUiStatus.verifying,
          message: AppStrings.boostVerifying,
        );
        notifyListeners();
        final verified = await _verifyBoostPurchase(
          userId: userId,
          transaction: value,
        );
        await _repository.completeStoreTransaction(value);
        switch (verified) {
          case Success(:final value):
            await _succeed(value);
          case Err(:final failure):
            await _fail(failure);
        }
    }
  }

  Future<void> _succeed(Boost boost) async {
    state = state.copyWith(
      status: PurchaseUiStatus.success,
      activeBoost: boost,
      message: AppStrings.boostSuccessTitle,
    );
    notifyListeners();
    await _analytics.logEvent(AnalyticsEvents.boostPurchaseSuccess);
    await _analytics.logEvent(AnalyticsEvents.boostActivated);
  }

  Future<void> _fail(Failure failure) async {
    final kind = failure is PurchaseFailure ? failure.kind : null;
    final status = _statusFor(failure);
    state = state.copyWith(
      status: status,
      message: FailureMessages.of(failure),
      errorKind: kind,
      clearErrorKind: kind == null,
    );
    notifyListeners();
    if (kind == PurchaseErrorKind.cancelled) {
      await _analytics.logEvent(AnalyticsEvents.boostPurchaseCancelled);
      return;
    }
    await _analytics.logEvent(AnalyticsEvents.boostPurchaseFailed);
  }

  PurchaseUiStatus _statusFor(Failure failure) {
    if (failure is PurchaseFailure) {
      return switch (failure.kind) {
        PurchaseErrorKind.cancelled => PurchaseUiStatus.cancelled,
        PurchaseErrorKind.unavailable => PurchaseUiStatus.unavailable,
        PurchaseErrorKind.storeDown => PurchaseUiStatus.unavailable,
        _ => PurchaseUiStatus.failed,
      };
    }
    if (failure is NetworkFailure) {
      return PurchaseUiStatus.failed;
    }
    return PurchaseUiStatus.failed;
  }
}
