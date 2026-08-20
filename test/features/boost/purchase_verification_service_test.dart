import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/boost/domain/config/boost_product_config.dart';
import 'package:mevora/features/boost/domain/entities/purchase_record.dart';
import 'package:mevora/features/boost/domain/services/purchase_verification_service.dart';

void main() {
  const config = BoostProductConfig();
  const service = PurchaseVerificationService(config: config);

  test('rejects empty uid, transaction, and unknown product', () {
    expect(
      service
          .decide(
            uid: '',
            productId: config.androidProductId,
            transactionId: 'tx',
            platform: PurchasePlatform.android,
          )
          .outcome,
      VerificationOutcome.invalidUid,
    );
    expect(
      service
          .decide(
            uid: 'u1',
            productId: config.androidProductId,
            transactionId: '',
            platform: PurchasePlatform.android,
          )
          .outcome,
      VerificationOutcome.invalidTransaction,
    );
    expect(
      service
          .decide(
            uid: 'u1',
            productId: 'com.other.boost',
            transactionId: 'tx',
            platform: PurchasePlatform.android,
          )
          .outcome,
      VerificationOutcome.invalidProduct,
    );
  });

  test('duplicate verified transaction does not proceed again', () {
    final existing = PurchaseRecord(
      purchaseId: 'android_tx1',
      userId: 'u1',
      productId: config.androidProductId,
      platform: PurchasePlatform.android,
      transactionId: 'tx1',
      status: PurchaseRecordStatus.verified,
      createdAt: DateTime.utc(2026, 8, 18),
    );
    final decision = service.decide(
      uid: 'u1',
      productId: config.androidProductId,
      transactionId: 'tx1',
      platform: PurchasePlatform.android,
      existing: existing,
    );
    expect(decision.outcome, VerificationOutcome.alreadyProcessed);
    expect(decision.purchaseId, 'android_tx1');
  });

  test('same receipt on another uid is rejected', () {
    final existing = PurchaseRecord(
      purchaseId: 'android_tx1',
      userId: 'u1',
      productId: config.androidProductId,
      platform: PurchasePlatform.android,
      transactionId: 'tx1',
      status: PurchaseRecordStatus.verified,
      createdAt: DateTime.utc(2026, 8, 18),
    );
    final decision = service.decide(
      uid: 'u2',
      productId: config.androidProductId,
      transactionId: 'tx1',
      platform: PurchasePlatform.android,
      existing: existing,
    );
    expect(decision.outcome, VerificationOutcome.duplicateOtherUser);
  });

  test('new matching product proceeds', () {
    final decision = service.decide(
      uid: 'u1',
      productId: config.iosProductId,
      transactionId: '1000000123',
      platform: PurchasePlatform.ios,
    );
    expect(decision.outcome, VerificationOutcome.proceed);
    expect(decision.purchaseId, 'ios_1000000123');
  });

  test('pack SKUs are allowed and map to a stable purchase id', () {
    final decision = service.decide(
      uid: 'u1',
      productId: 'com.mevora.app.boost.5',
      transactionId: 'GPA.pack5',
      platform: PurchasePlatform.android,
    );
    expect(decision.outcome, VerificationOutcome.proceed);
    expect(decision.purchaseId, 'android_GPA.pack5');
  });
}
