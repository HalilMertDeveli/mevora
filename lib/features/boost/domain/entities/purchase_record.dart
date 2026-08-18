import 'package:mevora/features/boost/domain/config/boost_product_config.dart';

enum PurchaseRecordStatus { pending, verified, failed }

/// Server-owned purchase ledger. No card, CVV, or bank data.
class PurchaseRecord {
  const PurchaseRecord({
    required this.purchaseId,
    required this.userId,
    required this.productId,
    required this.platform,
    required this.transactionId,
    required this.status,
    required this.createdAt,
    this.purchaseTokenHashOrReference,
    this.purchasedAt,
    this.verifiedAt,
  });

  final String purchaseId;
  final String userId;
  final String productId;
  final PurchasePlatform platform;
  final String transactionId;

  /// SHA-256 (or similar) of the store secret — never the raw Play token.
  final String? purchaseTokenHashOrReference;
  final PurchaseRecordStatus status;
  final DateTime? purchasedAt;
  final DateTime? verifiedAt;
  final DateTime createdAt;
}
