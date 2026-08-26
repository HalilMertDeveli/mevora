import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/services/app_logger.dart';

/// StoreKit finish-transaction helper. Consumable Boost is not restored by Apple.
class ApplePurchaseService {
  ApplePurchaseService({
    InAppPurchase? store,
    AppLogger? logger,
  }) : _store = store ?? InAppPurchase.instance,
       _logger = logger;

  final InAppPurchase _store;
  final AppLogger? _logger;

  Future<void> finish(PurchaseDetails details) async {
    if (!details.pendingCompletePurchase) {
      return;
    }
    try {
      await _store.completePurchase(details);
    } on Object catch (error, stackTrace) {
      _logger?.warning(
        'Apple purchase finish failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw const PurchaseException(
        'Satın alma tamamlanamadı. Lütfen tekrar dene.',
        kind: PurchaseErrorKind.failed,
      );
    }
  }

  /// Unfinished StoreKit transactions can be recovered. Finished consumables
  /// are not redelivered; active Boost is loaded from the Firebase UID ledger.
  Future<void> restoreConsumables() async {
    try {
      await _store.restorePurchases();
    } on Object catch (error, stackTrace) {
      _logger?.warning(
        'Apple restore failed; loading Boost from Firebase UID',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
