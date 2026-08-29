import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/features/subscription/data/repositories/premium_purchase_repository_impl.dart';
import 'package:mevora/features/subscription/domain/repositories/premium_purchase_repository.dart';

class PremiumServices {
  const PremiumServices({required this.purchaseRepository});

  final PremiumPurchaseRepository purchaseRepository;
}

PremiumServices createPremiumServices({
  required AuthUidSource uidSource,
  BackendCallable? backend,
}) {
  return PremiumServices(
    purchaseRepository: PremiumPurchaseRepositoryImpl(
      backend: backend ?? FirebaseFunctionsCallable(),
      uidSource: uidSource,
    ),
  );
}
