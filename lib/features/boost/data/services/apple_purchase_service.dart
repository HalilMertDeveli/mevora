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

  /// Boost is a consumable. StoreKit will not redeliver it after restore.
  /// Purchase history is the Firebase UID ledger, not the App Store.
  Future<void> restoreConsumables() async {
    _logger?.debug('Apple consumable restore skipped; history is Firebase UID');
  }
}
