import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/subscription/data/repositories/firestore_subscription_repository.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';
import 'package:mevora/features/subscription/presentation/controllers/subscription_controller.dart';

class SubscriptionServices {
  const SubscriptionServices({
    required this.repository,
    required this.controller,
  });

  final SubscriptionRepository repository;
  final SubscriptionController controller;
}

/// Wires Premium entitlement observation.
///
/// [premiumEnabled] is the product kill switch, not the user's entitlement.
/// With Premium switched off there is nothing on the client that consumes
/// entitlement, so the listener is not opened at all and no per-user read is
/// spent. The backend gate (`isUserPremium`) is untouched by this flag — a
/// paying user keeps their entitlement on the server either way.
SubscriptionServices createSubscriptionServices({
  required AuthUidSource uidSource,
  required bool premiumEnabled,
  SubscriptionRepository? repository,
}) {
  final SubscriptionRepository resolved =
      repository ??
      (premiumEnabled
          ? FirestoreSubscriptionRepository(uidSource: uidSource)
          : const DisabledSubscriptionRepository());
  final controller = SubscriptionController(repository: resolved)..start();
  return SubscriptionServices(repository: resolved, controller: controller);
}
