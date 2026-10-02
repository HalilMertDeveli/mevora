import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/build_guards.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/subscription/data/repositories/emulator_premium_billing_repository.dart';
import 'package:mevora/features/subscription/data/repositories/firestore_subscription_repository.dart';
import 'package:mevora/features/subscription/data/repositories/store_premium_billing_repository.dart';
import 'package:mevora/features/subscription/domain/config/premium_product_config.dart';
import 'package:mevora/features/subscription/domain/repositories/premium_billing_repository.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';
import 'package:mevora/features/subscription/presentation/controllers/subscription_controller.dart';

class SubscriptionServices {
  const SubscriptionServices({
    required this.repository,
    required this.controller,
    this.billing,
  });

  final SubscriptionRepository repository;
  final SubscriptionController controller;

  /// Buying Premium. Null when Premium is switched off — the paywall is simply
  /// unreachable then.
  final PremiumBillingRepository? billing;
}

/// Wires Premium entitlement observation, and the paywall's billing side.
///
/// [premiumEnabled] is the product kill switch, not the user's entitlement.
/// With Premium switched off there is nothing on the client that consumes
/// entitlement, so the listener is not opened at all and no per-user read is
/// spent. The backend gate (`isUserPremium`) is untouched by this flag — a
/// paying user keeps their entitlement on the server either way.
///
/// Billing is deliberately a separate object from [SubscriptionRepository]:
/// one sells, the other observes what the server granted. Keeping them apart
/// is what stops purchase-side code from ever being mistaken for entitlement.
SubscriptionServices createSubscriptionServices({
  required AuthUidSource uidSource,
  required bool premiumEnabled,
  SubscriptionRepository? repository,
  PremiumBillingRepository? billing,
  PremiumProductConfig? productConfig,
  BackendCallable? backend,
  AppLogger? logger,
  AnalyticsProvider? analytics,

  /// Swaps the store for a fixed-price test store whose purchases the
  /// Functions emulator verifies. Only ever true against the Emulator Suite.
  bool useEmulatorStore = false,

  /// The build's environment. The test store is honoured in development
  /// only; without an environment the real store is used.
  AppEnvironment? environment,
}) {
  final SubscriptionRepository resolved =
      repository ??
      (premiumEnabled
          ? FirestoreSubscriptionRepository(uidSource: uidSource)
          : const DisabledSubscriptionRepository());
  final controller = SubscriptionController(
    repository: resolved,
    analytics: analytics,
  )..start();

  final PremiumBillingRepository? resolvedBilling =
      billing ??
      (!premiumEnabled
          ? null
          : emulatorStoreAllowed(
              requested: useEmulatorStore,
              environment: environment,
            )
          ? EmulatorPremiumBillingRepository(
              backend: backend ?? FirebaseFunctionsCallable(),
              logger: logger,
            )
          : StorePremiumBillingRepository(
              backend: backend ?? FirebaseFunctionsCallable(),
              config: productConfig ?? PremiumProductConfig.fromEnvironment(),
              logger: logger,
              // Stamps each purchase with the account that made it, and
              // re-verifies purchases left unacknowledged by an earlier
              // session whenever an account is signed in.
              uidSource: uidSource,
            ));

  return SubscriptionServices(
    repository: resolved,
    controller: controller,
    billing: resolvedBilling,
  );
}
