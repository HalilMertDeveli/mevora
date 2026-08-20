import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/constants/app_strings.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/features/boost/domain/entities/boost_wallet.dart';
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
    expect(controller.state.product?.localizedPrice, '₺49,99');
    expect(controller.state.hasActiveBoost, isFalse);
    expect(controller.state.products, isNotEmpty);
  });

  test('already active boost blocks a second activation, not a pack purchase', () async {
    repository.wallet = const BoostWallet(balance: 2);
    await repository.activateBoost('u1');
    await controller.load();
    expect(controller.state.message, AppStrings.boostAlreadyActive);
    await controller.activate();
    expect(controller.state.message, AppStrings.boostAlreadyActive);
    await controller.purchase();
    expect(repository.verifyCalled, isTrue);
    expect(controller.state.status, PurchaseUiStatus.credited);
  });

  test('purchase waits for backend before crediting copy', () async {
    await controller.load();
    await controller.purchase();
    expect(repository.purchaseCalled, isTrue);
    expect(repository.verifyCalled, isTrue);
    expect(controller.state.status, PurchaseUiStatus.credited);
    expect(controller.state.message, AppStrings.boostCreditedTitle);
    expect(controller.state.hasActiveBoost, isFalse);
    expect(controller.state.balance, 1);
    expect(repository.lastCompleted?.transactionId, 'GPA.1234');
  });

  test('activate consumes balance and reports success only after server confirm', () async {
    repository.wallet = const BoostWallet(balance: 1);
    await controller.load();
    await controller.activate();
    expect(repository.activateCalled, isTrue);
    expect(controller.state.status, PurchaseUiStatus.success);
    expect(controller.state.message, AppStrings.boostSuccessTitle);
    expect(controller.state.hasActiveBoost, isTrue);
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
    expect(controller.state.balance, 0);
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
