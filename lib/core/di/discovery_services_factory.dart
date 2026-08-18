import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/features/discovery/data/repositories/discovery_repository_impl.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';

class DiscoveryServices {
  const DiscoveryServices({required this.discoveryRepository});

  final DiscoveryRepository discoveryRepository;
}

DiscoveryServices createDiscoveryServices({BackendCallable? backend}) {
  return DiscoveryServices(
    discoveryRepository: DiscoveryRepositoryImpl(
      backend: backend ?? FirebaseFunctionsCallable(),
    ),
  );
}
