import 'package:mevora/features/boost/domain/config/boost_product_config.dart';
import 'package:mevora/features/boost/domain/entities/purchase_record.dart';

enum VerificationOutcome {
  proceed,
  alreadyProcessed,
  invalidProduct,
  invalidUid,
  invalidTransaction,
  duplicateOtherUser,
}

class PurchaseVerificationDecision {
  const PurchaseVerificationDecision({
    required this.outcome,
    this.purchaseId,
  });

  final VerificationOutcome outcome;
  final String? purchaseId;

  bool get isAccepted =>
      outcome == VerificationOutcome.proceed ||
      outcome == VerificationOutcome.alreadyProcessed;
}

/// Validates product, uid, and transaction identity. Does **not** trust a
/// client "payment succeeded" flag. Store cryptographic verification happens
/// in Cloud Functions (ApplePurchaseVerifier / GooglePurchaseVerifier).
class PurchaseVerificationService {
  const PurchaseVerificationService({required this.config});

  final BoostProductConfig config;

  static String purchaseIdFor({
    required PurchasePlatform platform,
    required String transactionId,
  }) {
    return '${platform.name}_$transactionId';
  }

  PurchaseVerificationDecision decide({
    required String uid,
    required String productId,
    required String transactionId,
    required PurchasePlatform platform,
    PurchaseRecord? existing,
  }) {
    if (uid.trim().isEmpty) {
      return const PurchaseVerificationDecision(
        outcome: VerificationOutcome.invalidUid,
      );
    }
    if (transactionId.trim().isEmpty) {
      return const PurchaseVerificationDecision(
        outcome: VerificationOutcome.invalidTransaction,
      );
    }
    if (!config.isAllowedProductId(productId, platform)) {
      return const PurchaseVerificationDecision(
        outcome: VerificationOutcome.invalidProduct,
      );
    }

    final purchaseId = purchaseIdFor(
      platform: platform,
      transactionId: transactionId,
    );

    if (existing != null) {
      if (existing.userId != uid) {
        return PurchaseVerificationDecision(
          outcome: VerificationOutcome.duplicateOtherUser,
          purchaseId: purchaseId,
        );
      }
      if (existing.status == PurchaseRecordStatus.verified) {
        return PurchaseVerificationDecision(
          outcome: VerificationOutcome.alreadyProcessed,
          purchaseId: purchaseId,
        );
      }
    }

    return PurchaseVerificationDecision(
      outcome: VerificationOutcome.proceed,
      purchaseId: purchaseId,
    );
  }
}
