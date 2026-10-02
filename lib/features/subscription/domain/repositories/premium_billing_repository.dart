import 'package:mevora/features/subscription/domain/entities/premium_plan.dart';

/// Outcome of handing store evidence to the backend.
///
/// [isPremium] is the backend's answer, echoed so the paywall can stop
/// spinning immediately. It is *not* the source of truth — the entitlement
/// stream is. If the two ever disagree, the stream wins.
class PremiumVerificationResult {
  const PremiumVerificationResult({
    required this.ok,
    required this.isPremium,
    this.reason,
  });

  const PremiumVerificationResult.rejected(String this.reason)
    : ok = false,
      isPremium = false;

  /// The store accepted the order but the payment has not settled (cash,
  /// bank transfer). Nothing was verified because nothing has been paid; the
  /// purchase is verified on its own once it is.
  const PremiumVerificationResult.pending()
    : ok = false,
      isPremium = false,
      reason = pendingReason;

  /// [reason] of a purchase that is waiting on its payment.
  static const String pendingReason = 'purchase_pending';

  final bool ok;
  final bool isPremium;

  /// Backend's machine-readable refusal: `owned_by_other`, `unknown_product`,
  /// and so on — or [pendingReason], which is the store's, not the backend's.
  final String? reason;

  /// Not a refusal and not a grant: the payment is still outstanding.
  bool get isPending => reason == pendingReason;
}

/// Why a purchase did not complete, in terms the paywall can speak.
enum PremiumPurchaseFailure {
  storeUnavailable,
  productsUnavailable,
  cancelled,
  verificationRejected,

  /// Backend or store was momentarily unreachable. Worth retrying; nothing
  /// was lost, because the store keeps the purchase until it is acknowledged.
  transient,
  unknown,
}

class PremiumBillingException implements Exception {
  const PremiumBillingException(this.failure, {this.reason});

  final PremiumPurchaseFailure failure;
  final String? reason;

  @override
  String toString() => 'PremiumBillingException($failure, $reason)';
}

/// Buying Premium. Observing whether the user *has* Premium is a different
/// contract ([SubscriptionRepository]) on purpose: nothing here may be
/// mistaken for entitlement.
abstract class PremiumBillingRepository {
  /// Whether a store is reachable at all. False on desktop, in a plain
  /// emulator image without Play Services, and when billing is unavailable.
  Future<bool> isStoreAvailable();

  /// Plans the store actually offers, with the store's own prices. Empty when
  /// nothing is configured — never a fabricated plan.
  Future<List<PremiumPlan>> loadPlans();

  /// Opens the store's purchase sheet and, once the store reports a purchase,
  /// sends the evidence to the backend and returns the backend's answer.
  Future<PremiumVerificationResult> purchase(PremiumPlan plan);

  /// Re-presents whatever the store already knows this account owns. Same
  /// verification path as a first purchase — restore is not a shortcut.
  Future<PremiumVerificationResult> restore();
}
