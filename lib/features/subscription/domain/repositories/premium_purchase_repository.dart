import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';

class PremiumPurchaseResult {
  const PremiumPurchaseResult({
    required this.productId,
    required this.alreadyProcessed,
    this.status = const PremiumStatus(),
  });

  final String productId;
  final bool alreadyProcessed;
  final PremiumStatus status;
}

/// Store purchase + server verification for Premium (not Boost).
abstract class PremiumPurchaseRepository {
  Future<Result<List<String>>> loadStoreProductIds();

  Future<Result<PremiumPurchaseResult>> purchase({
    required String productId,
  });

  Future<Result<List<PremiumPurchaseResult>>> restore();
}
