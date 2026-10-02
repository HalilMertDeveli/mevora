import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/di/discovery_services_factory.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/discovery/data/repositories/discovery_repository_impl.dart';
import 'package:mevora/features/discovery/data/repositories/hybrid_discovery_repository.dart';

/// The distance gate can legitimately return an empty deck, and
/// HybridDiscoveryRepository pads a *successful* empty response with demo
/// profiles. In development that turns a correct gate into what looks like a
/// broken one: the demo seeds sit 1.8-28 km out and reappear as though nothing
/// had been excluded.
///
/// `DISCOVERY_NO_DEMO` exists so a QA run can see the server's real answer.
/// These tests pin both halves — the switch is off by default, so ordinary
/// development keeps its demo deck, and staging/production never padded at all.
void main() {
  group('discovery demo fallback', () {
    test('development keeps demo padding by default', () {
      // A plain `flutter test` run passes no --dart-define, so this is the
      // default path. If DISCOVERY_NO_DEMO ever starts defaulting to true,
      // every developer silently loses the demo deck and this fails.
      final services = createDiscoveryServices(
        config: const AppConfig(environment: AppEnvironment.development),
        backend: _UnusedBackend(),
      );
      final repository = services.discoveryRepository;
      expect(repository, isA<HybridDiscoveryRepository>());
      expect((repository as HybridDiscoveryRepository).allowDemoFallback, isTrue);
    });

    test('staging and production talk straight to the backend', () {
      for (final environment in [
        AppEnvironment.staging,
        AppEnvironment.production,
      ]) {
        final services = createDiscoveryServices(
          config: AppConfig(environment: environment),
          backend: _UnusedBackend(),
        );
        expect(
          services.discoveryRepository,
          isA<DiscoveryRepositoryImpl>(),
          reason: '$environment must not pad an empty deck',
        );
      }
    });

    test('a caller that names no environment gets the backend, not a demo', () {
      // The default used to be the other way round: no config meant "demo
      // allowed". What is not known to be development is production.
      final services = createDiscoveryServices(backend: _UnusedBackend());
      expect(services.discoveryRepository, isA<DiscoveryRepositoryImpl>());
    });

    test('padding still only fires on an empty live feed', () {
      // Guards the premise of the switch rather than re-testing the repository.
      // If padding stopped being conditional on emptiness, DISCOVERY_NO_DEMO
      // would no longer be the right lever and this file would mislead.
      final source = File(
        'lib/features/discovery/data/repositories/hybrid_discovery_repository.dart',
      ).readAsStringSync();
      expect(
        source,
        contains('if (real.isNotEmpty)'),
        reason: 'real candidates must keep winning over demo padding',
      );
      expect(
        source.indexOf('if (!allowDemoFallback)'),
        lessThan(source.indexOf('if (real.isNotEmpty)')),
        reason: 'the opt-out must short-circuit before any padding decision',
      );
    });
  });
}

class _UnusedBackend implements BackendCallable {
  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) {
    throw UnsupportedError('the factory must not call the backend');
  }
}
