import 'package:flutter/foundation.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/build_guards.dart';
import 'package:mevora/core/di/demo_social_hub.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/features/discovery/data/repositories/discovery_repository_impl.dart';
import 'package:mevora/features/discovery/data/repositories/hybrid_discovery_repository.dart';
import 'package:mevora/features/discovery/data/repositories/mock_discovery_repository.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';

class DiscoveryServices {
  const DiscoveryServices({required this.discoveryRepository});

  final DiscoveryRepository discoveryRepository;
}

DiscoveryServices createDiscoveryServices({
  AppConfig? config,
  BackendCallable? backend,
  DemoSocialHub? demoHub,
  String Function()? currentUid,
}) {
  // A release build has no demo deck to choose. Said first and with a
  // compile-time constant, so the demo repository, its profiles and their
  // portraits are not compiled into a store binary at all.
  if (kReleaseMode) {
    return DiscoveryServices(
      discoveryRepository: DiscoveryRepositoryImpl(
        backend: backend ?? FirebaseFunctionsCallable(),
      ),
    );
  }

  // The demo deck is built only for a build that may use it. A missing
  // config counts as production here as everywhere else: the real backend,
  // an honest empty deck, and no demo profile anywhere near it.
  MockDiscoveryRepository demoDeck() => MockDiscoveryRepository(
    demoHub: demoHub,
    currentUid: currentUid ?? () => demoHub?.uidSource.currentUid ?? 'self',
  );
  if (_forceMockOnly(config)) {
    return DiscoveryServices(discoveryRepository: demoDeck());
  }

  final remote = DiscoveryRepositoryImpl(
    backend: backend ?? FirebaseFunctionsCallable(),
  );
  final allowDemo =
      demoInfrastructureAllowed(environment: config?.environment) &&
      !_demoDiscoveryDisabled();
  if (!allowDemo) {
    return DiscoveryServices(discoveryRepository: remote);
  }
  return DiscoveryServices(
    discoveryRepository: HybridDiscoveryRepository(
      remote: remote,
      local: demoDeck(),
      allowDemoFallback: true,
      currentUid: currentUid ?? () => demoHub?.uidSource.currentUid ?? 'self',
    ),
  );
}

bool _forceMockOnly(AppConfig? config) {
  return mockDataSourceAllowed(
    define: const bool.fromEnvironment('USE_MOCK_DISCOVERY'),
    environment: config?.environment,
  );
}

/// Lets a QA run see the server's real empty deck.
///
/// HybridDiscoveryRepository pads with demo profiles when the live feed comes
/// back **successfully** but empty. That is exactly the state a distance-gate
/// test needs to observe, so without this switch a development build cannot
/// tell a correctly-gated empty result from a broken gate — the demo seeds sit
/// 1.8-28 km away and reappear as though nothing had been excluded.
///
/// Off by default, so ordinary development keeps its demo deck:
///   flutter run --dart-define=DISCOVERY_NO_DEMO=true
bool _demoDiscoveryDisabled() =>
    const bool.fromEnvironment('DISCOVERY_NO_DEMO');
