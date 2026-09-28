import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/subscription/domain/entities/premium_plan.dart';
import 'package:mevora/features/subscription/domain/repositories/premium_billing_repository.dart';

/// Stands in for Play Billing when the app runs against the Firebase Emulator
/// Suite, so the Premium purchase flow can be exercised end to end locally.
///
/// It replaces the store and nothing after it. A test purchase mints an opaque
/// token and hands it to the real `verifyPremiumPurchase` callable, where the
/// Functions emulator's test verifier answers for Google. From there it is the
/// production path: the catalogue check, the token-ownership claim, the
/// entitlement writer, the Firestore document — and the paywall only unlocks
/// once `SubscriptionScope` observes that document. Nothing here can flip the
/// UI to Premium on its own, exactly as with the real store.
///
/// Wired only when `AppConfig.useEmulators` is true, which is never the case
/// outside a development build. The backend half is independently gated on
/// `FUNCTIONS_EMULATOR`, so neither side alone can produce a test grant.
class EmulatorPremiumBillingRepository implements PremiumBillingRepository {
  EmulatorPremiumBillingRepository({
    required BackendCallable backend,
    this.testPrice = defaultTestPrice,
    AppLogger? logger,
  }) : _backend = backend,
       _logger = logger;

  /// What every test plan costs. Visibly a test figure, not a real price.
  static const String defaultTestPrice = '₺10,00';

  /// Marks tokens this store minted. The Functions emulator's test verifier
  /// accepts only these, and only while running under the emulator.
  static const String tokenPrefix = 'emulator-test:';

  /// Matches the Functions emulator's default Premium catalogue.
  static const String productId = 'mevora_premium';

  static const String _callable = 'verifyPremiumPurchase';

  final BackendCallable _backend;
  final AppLogger? _logger;
  final String testPrice;

  /// Tokens bought in this app session, so restore has something to present —
  /// the way a real store remembers what its account owns.
  final List<String> _owned = <String>[];
  int _sequence = 0;

  @override
  Future<bool> isStoreAvailable() async => true;

  @override
  Future<List<PremiumPlan>> loadPlans() async {
    return <PremiumPlan>[
      PremiumPlan(
        productId: productId,
        basePlanId: 'monthly',
        title: 'Premium · 1 Ay',
        description: 'Emulator test satın alımı — ücret alınmaz',
        formattedPrice: testPrice,
        period: PremiumPlanPeriod.monthly,
      ),
      PremiumPlan(
        productId: productId,
        basePlanId: 'yearly',
        title: 'Premium · 1 Yıl',
        description: 'Emulator test satın alımı — ücret alınmaz',
        formattedPrice: testPrice,
        period: PremiumPlanPeriod.yearly,
      ),
    ];
  }

  @override
  Future<PremiumVerificationResult> purchase(PremiumPlan plan) async {
    _sequence += 1;
    final nonce = '${DateTime.now().microsecondsSinceEpoch}-$_sequence';
    final token =
        '$tokenPrefix${plan.productId}:${plan.basePlanId ?? ''}:$nonce';
    final result = await _verify(token, plan.productId);
    if (result.ok) {
      _owned.add(token);
    }
    return result;
  }

  @override
  Future<PremiumVerificationResult> restore() async {
    if (_owned.isEmpty) {
      return const PremiumVerificationResult.rejected('nothing_to_restore');
    }
    // Same order as the real store path: any owned token that the backend
    // still grants is enough.
    PremiumVerificationResult last = const PremiumVerificationResult.rejected(
      'nothing_to_restore',
    );
    for (final token in List<String>.from(_owned)) {
      last = await _verify(token, productId);
      if (last.isPremium) {
        return last;
      }
    }
    return last;
  }

  Future<PremiumVerificationResult> _verify(
    String token,
    String productId,
  ) async {
    final Map<String, dynamic> response;
    try {
      // Always the Android contract: the emulator test verifier stands in for
      // Google only. iOS is not buildable from the Windows QA setup.
      response = await _backend.invoke(_callable, <String, dynamic>{
        'platform': PremiumPlatform.android.name,
        'purchaseToken': token,
        'productId': productId,
      });
    } on Object catch (error, stackTrace) {
      _logger?.warning(
        'Emulator Premium verification failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw const PremiumBillingException(PremiumPurchaseFailure.transient);
    }
    return PremiumVerificationResult(
      ok: response['ok'] == true,
      isPremium: response['isPremium'] == true,
      reason: response['reason'] as String?,
    );
  }
}
