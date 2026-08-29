import 'package:flutter/foundation.dart';
import 'package:mevora/features/subscription/domain/config/premium_pack_catalog.dart';
import 'package:mevora/features/subscription/domain/repositories/premium_purchase_repository.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';

enum PremiumPurchaseUiState {
  idle,
  loading,
  purchasing,
  verifying,
  success,
  cancelled,
  pending,
  failed,
  unavailable,
}

class PremiumPurchaseController extends ChangeNotifier {
  PremiumPurchaseController({
    required PremiumPurchaseRepository repository,
  }) : _repository = repository;

  final PremiumPurchaseRepository _repository;

  PremiumPurchaseUiState _state = PremiumPurchaseUiState.idle;
  String? _errorCode;
  List<String> _availableIds = const [];
  PremiumStatus _lastStatus = const PremiumStatus();

  PremiumPurchaseUiState get state => _state;
  String? get errorCode => _errorCode;
  List<String> get availableProductIds => _availableIds;
  PremiumStatus get lastStatus => _lastStatus;

  Future<void> load() async {
    _state = PremiumPurchaseUiState.loading;
    _errorCode = null;
    notifyListeners();
    final result = await _repository.loadStoreProductIds();
    result.when(
      success: (ids) {
        _availableIds = ids;
        _state = ids.isEmpty
            ? PremiumPurchaseUiState.unavailable
            : PremiumPurchaseUiState.idle;
      },
      err: (failure) {
        _errorCode = failure.message;
        _state = PremiumPurchaseUiState.unavailable;
      },
    );
    notifyListeners();
  }

  Future<void> buyMonth() => buy(PremiumPackCatalog.month);

  Future<void> buyYear() => buy(PremiumPackCatalog.year);

  Future<void> buy(String productId) async {
    _state = PremiumPurchaseUiState.purchasing;
    _errorCode = null;
    notifyListeners();
    final result = await _repository.purchase(productId: productId);
    result.when(
      success: (value) {
        _lastStatus = value.status;
        _state = PremiumPurchaseUiState.success;
      },
      err: (failure) {
        _errorCode = failure.message;
        _state = switch (failure.message) {
          'purchase_cancelled' => PremiumPurchaseUiState.cancelled,
          'purchase_pending' => PremiumPurchaseUiState.pending,
          'store_unavailable' || 'product_missing' =>
            PremiumPurchaseUiState.unavailable,
          _ => PremiumPurchaseUiState.failed,
        };
      },
    );
    notifyListeners();
  }

  Future<void> restore() async {
    _state = PremiumPurchaseUiState.verifying;
    _errorCode = null;
    notifyListeners();
    final result = await _repository.restore();
    result.when(
      success: (values) {
        if (values.isEmpty) {
          _state = PremiumPurchaseUiState.failed;
          _errorCode = 'nothing_to_restore';
        } else {
          _lastStatus = values.last.status;
          _state = PremiumPurchaseUiState.success;
        }
      },
      err: (failure) {
        _errorCode = failure.message;
        _state = PremiumPurchaseUiState.failed;
      },
    );
    notifyListeners();
  }
}
