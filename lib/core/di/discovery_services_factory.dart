import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/features/discovery/data/repositories/discovery_repository_impl.dart';
import 'package:mevora/features/discovery/data/repositories/mock_discovery_repository.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';

class DiscoveryServices {
  const DiscoveryServices({required this.discoveryRepository});

  final DiscoveryRepository discoveryRepository;
}

DiscoveryServices createDiscoveryServices({
  AppConfig? config,
  BackendCallable? backend,
}) {
  final useMock = _useMockDiscovery(config);
  if (useMock) {
    return DiscoveryServices(
      discoveryRepository: MockDiscoveryRepository(),
    );
  }
  return DiscoveryServices(
    discoveryRepository: DiscoveryRepositoryImpl(
      backend: backend ?? FirebaseFunctionsCallable(),
    ),
  );
}

bool _useMockDiscovery(AppConfig? config) {
  const fromEnv = bool.fromEnvironment('USE_MOCK_DISCOVERY');
  if (fromEnv) {
    return true;
  }
  if (config == null) {
    return false;
  }
  return config.environment.isDevelopment;
}
