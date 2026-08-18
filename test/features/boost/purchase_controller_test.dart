import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/constants/app_strings.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/features/boost/domain/entities/purchase_flow_state.dart';
import 'package:mevora/features/boost/domain/usecases/get_active_boost.dart';
import 'package:mevora/features/boost/domain/usecases/get_boost_product.dart';
import 'package:mevora/features/boost/domain/usecases/purchase_boost.dart';
import 'package:mevora/features/boost/domain/usecases/verify_boost_purchase.dart';
import 'package:mevora/features/boost/presentation/controllers/purchase_controller.dart';

import '../../helpers/fake_purchase_repository.dart';

void main() {
  late FakePurchaseRepository repository;
  late PurchaseController controller;

  setUp(() {
    repository = FakePurchaseRepository();
    controller = PurchaseController(
      userId: 'u1',
      getBoostProduct: GetBoostProduct(repository),
      purchaseBoost: PurchaseBoost(repository),
      verifyBoostPurchase: VerifyBoostPurchase(repository),
      getActiveBoost: GetActiveBoost(repository),
      repository: repository,
    );
  });

  tearDown(() => controller.dispose());

  test('load shows store product without activating', () async {
    await controller.load();
    expect(controller.state.status, PurchaseUiStatus.productLoaded);
    expect(controller.state.product?.localizedPrice, '₺29,99');
    expect(controller.state.hasActiveBoost, isFalse);
  });

  test('already active boost blocks a second purchase', () async {
    repository.activeBoost = (await repository.verifyBoostPurchase(
      userId: 'u1',
      transaction: repository.transaction!,
    )).valueOrNull;
    await controller.load();
    expect(controller.state.message, AppStrings.boostAlreadyActive);
    await controller.purchase();
    expect(controller.state.message, AppStrings.boostAlreadyActive);
  });

  test('purchase waits for backend before success copy', () async {
    await controller.load();
    await controller.purchase();
    expect(repository.purchaseCalled, isTrue);
    expect(repository.verifyCalled, isTrue);
    expect(controller.state.status, PurchaseUiStatus.success);
    expect(controller.state.message, AppStrings.boostSuccessTitle);
    expect(repository.lastCompleted?.transactionId, 'GPA.1234');
  });

  test('cancelled purchase uses cancelled state', () async {
    await controller.load();
    repository.purchaseFailure = const PurchaseFailure(
      AppStrings.boostPurchaseCancelled,
      kind: PurchaseErrorKind.cancelled,
    );
    await controller.purchase();
    expect(controller.state.status, PurchaseUiStatus.cancelled);
    expect(repository.verifyCalled, isFalse);
  });

  test('verification failure does not claim boost is active', () async {
    await controller.load();
    repository.verifyFailure = const PurchaseFailure(
      AppStrings.boostVerificationFailed,
      kind: PurchaseErrorKind.verificationFailed,
    );
    await controller.purchase();
    expect(controller.state.status, PurchaseUiStatus.failed);
    expect(controller.state.message, AppStrings.boostVerificationFailed);
    expect(controller.state.hasActiveBoost, isFalse);
  });

  test('unavailable store maps to unavailable', () async {
    repository.productFailure = const PurchaseFailure(
      AppStrings.boostStoreUnavailable,
      kind: PurchaseErrorKind.unavailable,
    );
    await controller.load();
    expect(controller.state.status, PurchaseUiStatus.unavailable);
  });
}
