import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/bootstrap.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/di/subscription_services_factory.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/boost/data/datasources/emulator_store_purchase_data_source.dart';
import 'package:mevora/features/boost/data/datasources/store_purchase_data_source.dart';
import 'package:mevora/features/boost/domain/config/boost_pack_catalog.dart';
import 'package:mevora/features/boost/domain/config/boost_product_config.dart';
import 'package:mevora/features/subscription/data/repositories/emulator_premium_billing_repository.dart';
import 'package:mevora/features/subscription/data/repositories/store_premium_billing_repository.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';

class RecordingBackend implements BackendCallable {
  RecordingBackend(this.reply);

  Map<String, dynamic> reply;
  final List<Map<String, dynamic>> calls = <Map<String, dynamic>>[];
  final List<String> names = <String>[];

  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    names.add(name);
    calls.add(Map<String, dynamic>.from(data ?? const <String, dynamic>{}));
    return reply;
  }
}

class _NoUid implements AuthUidSource {
  @override
  String? get currentUid => null;

  @override
  Stream<String?> watchUid() => const Stream<String?>.empty();
}

void main() {
  group('Boost emulator store', () {
    test('offers every storefront pack at the test price', () async {
      final store = EmulatorStorePurchaseDataSource();
      addTearDown(store.dispose);

      final products = await store.loadProducts(const BoostProductConfig());

      expect(
        products.map((p) => p.productId).toSet(),
        BoostPackCatalog.storefrontSkus,
      );
      for (final product in products) {
        expect(product.displayPrice, '₺10,00');
        expect(product.available, isTrue);
      }
    });

    test(
      'a buy reports a purchase with a token the emulator recognises',
      () async {
        final store = EmulatorStorePurchaseDataSource();
        addTearDown(store.dispose);
        final products = await store.loadProducts(const BoostProductConfig());

        final next = store.purchaseEvents.first;
        await store.buy(products.first);
        final event = await next;

        expect(event.status, StorePurchaseStatus.purchased);
        expect(event.transaction?.productId, products.first.productId);
        expect(
          event.transaction?.purchaseToken,
          startsWith(EmulatorStorePurchaseDataSource.tokenPrefix),
        );
      },
    );

    test(
      'reports after buy returns, the way a real store sheet does',
      () async {
        final store = EmulatorStorePurchaseDataSource();
        addTearDown(store.dispose);
        final products = await store.loadProducts(const BoostProductConfig());
        final seen = <StorePurchaseEvent>[];
        final sub = store.purchaseEvents.listen(seen.add);
        addTearDown(sub.cancel);

        await store.buy(products.first);
        expect(seen, isEmpty, reason: 'must not report synchronously');
        await Future<void>.delayed(Duration.zero);
        expect(seen, hasLength(1));
      },
    );
  });

  group('Premium emulator store', () {
    test('offers monthly and yearly at the test price', () async {
      final billing = EmulatorPremiumBillingRepository(
        backend: RecordingBackend(const <String, dynamic>{}),
      );
      final plans = await billing.loadPlans();

      expect(plans.map((p) => p.basePlanId), <String>['monthly', 'yearly']);
      for (final plan in plans) {
        expect(plan.formattedPrice, '₺10,00');
        expect(plan.productId, EmulatorPremiumBillingRepository.productId);
      }
    });

    test('a purchase is verified by the backend, not granted locally', () async {
      final backend = RecordingBackend(<String, dynamic>{
        'ok': true,
        'isPremium': true,
      });
      final billing = EmulatorPremiumBillingRepository(backend: backend);
      final plans = await billing.loadPlans();

      final result = await billing.purchase(plans.first);

      expect(result.isPremium, isTrue);
      expect(backend.names, <String>['verifyPremiumPurchase']);
      final sent = backend.calls.single;
      expect(sent['platform'], 'android');
      expect(
        sent['purchaseToken'],
        startsWith(
          '${EmulatorPremiumBillingRepository.tokenPrefix}mevora_premium:monthly:',
        ),
      );
      // Evidence only — never a claim about the outcome.
      expect(sent.keys, isNot(contains('isPremium')));
      expect(sent.keys, isNot(contains('expiresAt')));
    });

    test('a backend refusal is a refusal, even in the emulator', () async {
      final backend = RecordingBackend(<String, dynamic>{
        'ok': false,
        'isPremium': false,
        'reason': 'owned_by_other',
      });
      final billing = EmulatorPremiumBillingRepository(backend: backend);
      final plans = await billing.loadPlans();

      final result = await billing.purchase(plans.first);

      expect(result.isPremium, isFalse);
      expect(result.reason, 'owned_by_other');
    });

    test('restore re-presents what was bought, through the backend', () async {
      final backend = RecordingBackend(<String, dynamic>{
        'ok': true,
        'isPremium': true,
      });
      final billing = EmulatorPremiumBillingRepository(backend: backend);
      final plans = await billing.loadPlans();
      await billing.purchase(plans.last);
      final bought = backend.calls.single['purchaseToken'];

      final restored = await billing.restore();

      expect(restored.isPremium, isTrue);
      expect(backend.calls, hasLength(2));
      expect(backend.calls.last['purchaseToken'], bought);
    });

    test('restore with nothing bought says so', () async {
      final backend = RecordingBackend(const <String, dynamic>{});
      final billing = EmulatorPremiumBillingRepository(backend: backend);

      final restored = await billing.restore();

      expect(restored.isPremium, isFalse);
      expect(restored.reason, 'nothing_to_restore');
      expect(backend.calls, isEmpty);
    });
  });

  group('wiring', () {
    test('the emulator store is used when asked for', () {
      // The other branch builds the real Play Billing store, which needs a
      // platform channel a unit test does not have; the default being `false`
      // is what keeps it the choice everywhere else.
      final on = createSubscriptionServices(
        uidSource: _NoUid(),
        premiumEnabled: true,
        repository: const DisabledSubscriptionRepository(),
        backend: RecordingBackend(const <String, dynamic>{}),
        useEmulatorStore: true,
      );
      addTearDown(on.controller.dispose);

      expect(on.billing, isA<EmulatorPremiumBillingRepository>());
      expect(on.billing, isNot(isA<StorePremiumBillingRepository>()));
    });

    test('Premium switched off offers no store at all, emulator or not', () {
      final services = createSubscriptionServices(
        uidSource: _NoUid(),
        premiumEnabled: false,
        repository: const DisabledSubscriptionRepository(),
        useEmulatorStore: true,
      );
      addTearDown(services.controller.dispose);

      expect(services.billing, isNull);
    });

    test('Premium surfaces in debug development builds only', () {
      // flutter test runs in debug mode, so this is the F5 case.
      expect(resolvePremiumEnabled(AppEnvironment.development), isTrue);
      expect(resolvePremiumEnabled(AppEnvironment.staging), isFalse);
      expect(resolvePremiumEnabled(AppEnvironment.production), isFalse);
    });
  });
}
