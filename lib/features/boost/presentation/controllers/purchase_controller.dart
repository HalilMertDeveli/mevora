import 'package:flutter/foundation.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/analytics/noop_analytics_provider.dart';
import 'package:mevora/core/constants/app_strings.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/failure_messages.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/features/boost/domain/entities/boost_history_entry.dart';
import 'package:mevora/features/boost/domain/entities/boost_product.dart';
import 'package:mevora/features/boost/domain/entities/boost_wallet.dart';
import 'package:mevora/features/boost/domain/entities/purchase_flow_state.dart';
import 'package:mevora/features/boost/domain/usecases/activate_boost.dart';
import 'package:mevora/features/boost/domain/usecases/get_active_boost.dart';
import 'package:mevora/features/boost/domain/usecases/get_boost_history.dart';
import 'package:mevora/features/boost/domain/usecases/get_boost_product.dart';
import 'package:mevora/features/boost/domain/usecases/get_boost_products.dart';
import 'package:mevora/features/boost/domain/usecases/get_boost_wallet.dart';
import 'package:mevora/features/boost/domain/usecases/purchase_boost.dart';
import 'package:mevora/features/boost/domain/usecases/verify_boost_purchase.dart';
import 'package:mevora/features/boost/domain/repositories/purchase_repository.dart';

class PurchaseViewState {
  const PurchaseViewState({
    this.status = PurchaseUiStatus.initial,
    this.product,
    this.products = const [],
    this.wallet = const BoostWallet(),
    this.history = const [],
    this.activeBoost,
    this.message,
    this.errorKind,
  });

  final PurchaseUiStatus status;
  final BoostProduct? product;
  final List<BoostProduct> products;
  final BoostWallet wallet;
  final List<BoostHistoryEntry> history;
  final Boost? activeBoost;
  final String? message;
  final PurchaseErrorKind? errorKind;

  bool get hasActiveBoost => activeBoost != null;
  bool get canActivate => wallet.hasBoosts && !hasActiveBoost;
  int get balance => wallet.balance;

  PurchaseViewState copyWith({
    PurchaseUiStatus? status,
    BoostProduct? product,
    List<BoostProduct>? products,
    BoostWallet? wallet,
    List<BoostHistoryEntry>? history,
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
      products: products ?? this.products,
      wallet: wallet ?? this.wallet,
      history: history ?? this.history,
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
    GetBoostProducts? getBoostProducts,
    GetBoostWallet? getBoostWallet,
    GetBoostHistory? getBoostHistory,
    ActivateBoost? activateBoost,
    AnalyticsProvider? analytics,
  }) : _getBoostProduct = getBoostProduct,
       _getBoostProducts = getBoostProducts ?? GetBoostProducts(repository),
       _purchaseBoost = purchaseBoost,
       _verifyBoostPurchase = verifyBoostPurchase,
       _getActiveBoost = getActiveBoost,
       _getWallet = getBoostWallet ?? GetBoostWallet(repository),
       _getHistory = getBoostHistory ?? GetBoostHistory(repository),
       _activateBoost = activateBoost ?? ActivateBoost(repository),
       _repository = repository,
       _analytics = analytics ?? const NoopAnalyticsProvider();

  final String userId;
  final GetBoostProduct _getBoostProduct;
  final GetBoostProducts _getBoostProducts;
  final PurchaseBoost _purchaseBoost;
  final VerifyBoostPurchase _verifyBoostPurchase;
  final GetActiveBoost _getActiveBoost;
  final GetBoostWallet _getWallet;
  final GetBoostHistory _getHistory;
  final ActivateBoost _activateBoost;
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
    final packs = await _getBoostProducts();
    final wallet = await _getWallet(userId);
    final history = await _getHistory(userId);
    final single = await _getBoostProduct();

    Boost? boost;
    switch (active) {
      case Success(:final value):
        boost = value;
      case Err():
        break;
    }

    final products = switch (packs) {
      Success(:final value) => value,
      Err() => <BoostProduct>[
        if (single.valueOrNull != null) single.valueOrNull!,
      ],
    };

    final loadedWallet = wallet.valueOrNull ?? const BoostWallet();
    final loadedHistory = history.valueOrNull ?? const <BoostHistoryEntry>[];
    final product = products.isNotEmpty
        ? products.first
        : single.valueOrNull;

    if (products.isEmpty && single is Err<BoostProduct>) {
      final failure = single.failure;
      state = state.copyWith(
        status: _statusFor(failure),
        message: FailureMessages.of(failure),
        errorKind: failure is PurchaseFailure ? failure.kind : null,
        wallet: loadedWallet,
        history: loadedHistory,
        activeBoost: boost,
        clearBoost: boost == null,
      );
      notifyListeners();
      return;
    }

    state = state.copyWith(
      status: PurchaseUiStatus.productLoaded,
      product: product,
      products: products,
      wallet: loadedWallet,
      history: loadedHistory,
      activeBoost: boost,
      clearBoost: boost == null,
      message: boost != null ? AppStrings.boostAlreadyActive : null,
      errorKind: boost != null ? PurchaseErrorKind.alreadyActive : null,
      clearMessage: boost == null,
      clearErrorKind: boost == null,
    );
    notifyListeners();
  }

  Future<void> purchase([BoostProduct? pack]) async {
    final product = pack ?? state.product;
    if (product == null) {
      return;
    }
    if (!product.available) {
      state = state.copyWith(
        status: PurchaseUiStatus.unavailable,
        message: AppStrings.boostStoreUnavailable,
        errorKind: PurchaseErrorKind.unavailable,
      );
      notifyListeners();
      return;
    }

    state = state.copyWith(
      status: PurchaseUiStatus.purchasing,
      product: product,
      message: AppStrings.boostPurchasing,
      clearErrorKind: true,
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
            await _credited(value.balance, value.boostCount);
          case Err(:final failure):
            await _fail(failure);
        }
    }
  }

  Future<void> activate() async {
    if (state.hasActiveBoost) {
      state = state.copyWith(
        status: PurchaseUiStatus.failed,
        message: AppStrings.boostAlreadyActive,
        errorKind: PurchaseErrorKind.alreadyActive,
      );
      notifyListeners();
      return;
    }
    if (!state.wallet.hasBoosts) {
      state = state.copyWith(
        status: PurchaseUiStatus.failed,
        message: AppStrings.boostInsufficientBalance,
        errorKind: PurchaseErrorKind.insufficientBalance,
      );
      notifyListeners();
      return;
    }

    state = state.copyWith(
      status: PurchaseUiStatus.activating,
      message: AppStrings.boostVerifying,
      clearErrorKind: true,
    );
    notifyListeners();

    final result = await _activateBoost(userId);
    switch (result) {
      case Success(:final value):
        await _activated(value);
      case Err(:final failure):
        await _fail(failure);
    }
  }

  Future<void> _credited(int balance, int added) async {
    final history = await _getHistory(userId);
    state = state.copyWith(
      status: PurchaseUiStatus.credited,
      wallet: BoostWallet(balance: balance),
      history: history.valueOrNull ?? state.history,
      message: AppStrings.boostCreditedTitle,
      clearErrorKind: true,
    );
    notifyListeners();
    await _analytics.logEvent(AnalyticsEvents.boostPurchaseSuccess);
  }

  Future<void> _activated(Boost boost) async {
    final wallet = await _getWallet(userId);
    final history = await _getHistory(userId);
    state = state.copyWith(
      status: PurchaseUiStatus.success,
      activeBoost: boost,
      wallet: wallet.valueOrNull ??
          BoostWallet(balance: (state.wallet.balance - 1).clamp(0, 1 << 30)),
      history: history.valueOrNull ?? state.history,
      message: AppStrings.boostSuccessTitle,
      clearErrorKind: true,
    );
    notifyListeners();
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
