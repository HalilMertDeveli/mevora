import 'package:mevora/features/boost/domain/config/boost_product_config.dart';

/// Opaque store receipt handed to Cloud Functions. UI must not parse it.
class StoreTransaction {
  const StoreTransaction({
    required this.platform,
    required this.productId,
    required this.transactionId,
    this.purchaseToken,
    this.signedTransaction,
    this.receiptData,
    this.localVerificationData,
  });

  final PurchasePlatform platform;
  final String productId;
  final String transactionId;

  /// Google Play purchase token. Sent only to verifyBoostPurchase over HTTPS.
  final String? purchaseToken;

  /// StoreKit 2 JWS. Sent only to verifyBoostPurchase.
  final String? signedTransaction;

  /// Legacy iOS receipt. Sent only to verifyBoostPurchase.
  final String? receiptData;

  /// Platform local payload; never logged.
  final String? localVerificationData;
}
