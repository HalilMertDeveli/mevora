import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/services/app_logger.dart';

/// Play Billing consume helper. Unconsumed purchases may be redelivered;
/// verification is idempotent and keyed by Firebase UID.
class GooglePurchaseService {
  GooglePurchaseService({
    InAppPurchase? store,
    AppLogger? logger,
  }) : _store = store ?? InAppPurchase.instance,
       _logger = logger;

  final InAppPurchase _store;
  final AppLogger? _logger;

  Future<void> consume(PurchaseDetails details) async {
    try {
      final addition = _store
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      await addition.consumePurchase(details);
    } on Object catch (error, stackTrace) {
      _logger?.warning(
        'Google Play consume failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw const PurchaseException(
        'Satın alma tamamlanamadı. Lütfen tekrar dene.',
        kind: PurchaseErrorKind.failed,
      );
    }
  }

  /// What Play holds for this account: purchases that were never consumed,
  /// and its subscriptions. Unlike [restoreUnconsumed] it answers the caller
  /// alone, instead of replaying every purchase to every listener of the
  /// shared purchase stream.
  Future<List<PurchaseDetails>> unconsumedPurchases() async {
    final addition = _store
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final response = await addition.queryPastPurchases();
    return response.pastPurchases;
  }

  Future<void> restoreUnconsumed() async {
    try {
      await _store.restorePurchases();
    } on Object catch (error, stackTrace) {
      _logger?.warning(
        'Google Play restore failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
