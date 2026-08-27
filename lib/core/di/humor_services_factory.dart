import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/features/humor/data/datasources/functions_humor_data_source.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/domain/repositories/humor_repository.dart';

class HumorServices {
  const HumorServices({required this.repository});

  final HumorRepository repository;
}

/// Prefer mock by default for MVP local UI safety.
/// Pass `--dart-define=USE_MOCK_HUMOR=false` to hit Cloud Functions.
HumorServices createHumorServices({
  AppConfig? config,
  BackendCallable? backend,
  HumorRepository? repository,
}) {
  if (repository != null) {
    return HumorServices(repository: repository);
  }
  const useMock = bool.fromEnvironment(
    'USE_MOCK_HUMOR',
    defaultValue: true,
  );
  if (useMock) {
    return HumorServices(
      repository: HumorRepositoryImpl(dataSource: MockHumorDataSource()),
    );
  }
  return HumorServices(
    repository: HumorRepositoryImpl(
      dataSource: FunctionsHumorDataSource(
        backend: backend ??
            FirebaseFunctionsCallable(
              region: config?.functionsRegion ?? 'europe-west1',
            ),
      ),
    ),
  );
}
