import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/features/subscription/domain/entities/premium_plan.dart';
import 'package:mevora/features/subscription/domain/repositories/premium_billing_repository.dart';

/// Where the paywall is in the purchase sequence.
///
/// [verifying] is deliberately distinct from [purchasing]: the store has said
/// yes but Mevora has not, and the user should see that the app is still
/// checking rather than a screen that already looks unlocked.
enum PremiumPurchaseStage {
  idle,
  loadingPlans,

  /// Store reachable, plans in hand.
  ready,

  /// No plans to show — nothing configured, or the store is unreachable.
  unavailable,

  /// The store sheet is up.
  purchasing,

  /// The store is done; the backend is checking the token.
  verifying,

  /// The backend granted Premium. The entitlement stream is the real signal;
  /// this only stops the spinner.
  purchased,

  restoring,
  cancelled,
  failed,
}

/// Drives the paywall. Owns no entitlement.
///
/// The only thing this class can do on success is stop spinning and say so.
/// Whether the user *is* Premium is answered by `SubscriptionScope`, which
/// reads the server-written entitlement — so a bug here can, at worst, show a
/// wrong message, never a wrong unlock.
class PremiumPurchaseController extends ChangeNotifier {
  PremiumPurchaseController({
    required PremiumBillingRepository billing,
    AnalyticsProvider? analytics,
  }) : _billing = billing,
       _analytics = analytics;

  final PremiumBillingRepository _billing;
  final AnalyticsProvider? _analytics;

  /// Fire-and-forget. A failed analytics call must never fail a purchase.
  void _track(String event) {
    final analytics = _analytics;
    if (analytics == null) {
      return;
    }
    unawaited(analytics.logEvent(event).catchError((Object _) {}));
  }

  PremiumPurchaseStage _stage = PremiumPurchaseStage.idle;
  List<PremiumPlan> _plans = const [];
  PremiumPlan? _selected;
  PremiumPurchaseFailure? _failure;
  String? _reason;
  bool _disposed = false;

  PremiumPurchaseStage get stage => _stage;
  List<PremiumPlan> get plans => _plans;
  PremiumPlan? get selected => _selected;
  PremiumPurchaseFailure? get failure => _failure;

  /// Backend's machine-readable refusal, when there was one.
  String? get reason => _reason;

  bool get isBusy =>
      _stage == PremiumPurchaseStage.loadingPlans ||
      _stage == PremiumPurchaseStage.purchasing ||
      _stage == PremiumPurchaseStage.verifying ||
      _stage == PremiumPurchaseStage.restoring;

  Future<void> loadPlans() async {
    if (_stage == PremiumPurchaseStage.loadingPlans) {
      return;
    }
    _set(stage: PremiumPurchaseStage.loadingPlans, clearError: true);
    try {
      final plans = await _billing.loadPlans();
      if (_disposed) {
        return;
      }
      _plans = plans;
      // An empty catalogue is not an error state to apologise for; it is a
      // configuration fact. Either way there is nothing to sell here.
      _selected = plans.isEmpty ? null : _preferred(plans);
      _track(AnalyticsEvents.premiumPaywallViewed);
      _set(
        stage: plans.isEmpty
            ? PremiumPurchaseStage.unavailable
            : PremiumPurchaseStage.ready,
      );
    } on PremiumBillingException catch (error) {
      _fail(error, fallback: PremiumPurchaseStage.unavailable);
    }
  }

  void select(PremiumPlan plan) {
    if (isBusy) {
      return;
    }
    _selected = plan;
    notifyListeners();
  }

  Future<void> buySelected() async {
    final plan = _selected;
    if (plan == null || isBusy) {
      return;
    }
    _track(AnalyticsEvents.premiumPurchaseStarted);
    _set(stage: PremiumPurchaseStage.purchasing, clearError: true);
    try {
      // The repository spans both steps, so the UI moves to "verifying" as
      // soon as the sheet is dismissed rather than waiting for the result.
      final result = await _billing.purchase(plan);
      if (_disposed) {
        return;
      }
      _applyResult(result);
    } on PremiumBillingException catch (error) {
      _fail(error);
    }
  }

  Future<void> restore() async {
    if (isBusy) {
      return;
    }
    _track(AnalyticsEvents.premiumRestoreStarted);
    _set(stage: PremiumPurchaseStage.restoring, clearError: true);
    try {
      final result = await _billing.restore();
      if (_disposed) {
        return;
      }
      _applyResult(result);
    } on PremiumBillingException catch (error) {
      _fail(error);
    }
  }

  /// Returns the paywall to a state the user can act from after an error.
  void acknowledge() {
    if (isBusy) {
      return;
    }
    _set(
      stage: _plans.isEmpty
          ? PremiumPurchaseStage.unavailable
          : PremiumPurchaseStage.ready,
      clearError: true,
    );
  }

  void _applyResult(PremiumVerificationResult result) {
    if (result.isPremium) {
      _track(
        _stage == PremiumPurchaseStage.restoring
            ? AnalyticsEvents.premiumRestoreSuccess
            : AnalyticsEvents.premiumPurchaseSuccess,
      );
      _set(stage: PremiumPurchaseStage.purchased, clearError: true);
      return;
    }
    // Verified and refused. Not a crash and not a grant — say why.
    _track(AnalyticsEvents.premiumPurchaseFailed);
    _failure = PremiumPurchaseFailure.verificationRejected;
    _reason = result.reason;
    _set(stage: PremiumPurchaseStage.failed);
  }

  void _fail(
    PremiumBillingException error, {
    PremiumPurchaseStage fallback = PremiumPurchaseStage.failed,
  }) {
    if (_disposed) {
      return;
    }
    _track(
      error.failure == PremiumPurchaseFailure.cancelled
          ? AnalyticsEvents.premiumPurchaseCancelled
          : AnalyticsEvents.premiumPurchaseFailed,
    );
    _failure = error.failure;
    _reason = error.reason;
    _set(
      stage: error.failure == PremiumPurchaseFailure.cancelled
          ? PremiumPurchaseStage.cancelled
          : fallback,
    );
  }

  /// Yearly first when the store offers one — it is the plan most people mean
  /// by "subscribe". Falls back to whatever came first.
  PremiumPlan _preferred(List<PremiumPlan> plans) {
    for (final plan in plans) {
      if (plan.period == PremiumPlanPeriod.yearly) {
        return plan;
      }
    }
    return plans.first;
  }

  void _set({required PremiumPurchaseStage stage, bool clearError = false}) {
    if (_disposed) {
      return;
    }
    if (clearError) {
      _failure = null;
      _reason = null;
    }
    _stage = stage;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
