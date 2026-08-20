import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
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
  final local = MockDiscoveryRepository(
    demoHub: demoHub,
    currentUid: currentUid ?? () => demoHub?.uidSource.currentUid ?? 'self',
  );
  if (_forceMockOnly(config)) {
    return DiscoveryServices(discoveryRepository: local);
  }

  final remote = DiscoveryRepositoryImpl(
    backend: backend ?? FirebaseFunctionsCallable(),
  );
  final allowDemo = config?.environment.isDevelopment ?? true;
  if (!allowDemo) {
    return DiscoveryServices(discoveryRepository: remote);
  }
  return DiscoveryServices(
    discoveryRepository: HybridDiscoveryRepository(
      remote: remote,
      local: local,
      allowDemoFallback: true,
      currentUid: currentUid ?? () => demoHub?.uidSource.currentUid ?? 'self',
    ),
  );
}

bool _forceMockOnly(AppConfig? config) {
  const fromEnv = bool.fromEnvironment('USE_MOCK_DISCOVERY');
  return fromEnv;
}
