import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/features/relationship/data/datasources/functions_relationship_data_source.dart';
import 'package:mevora/features/relationship/data/datasources/mock_relationship_data_source.dart';
import 'package:mevora/features/relationship/data/repositories/relationship_repository_impl.dart';
import 'package:mevora/features/relationship/domain/repositories/relationship_repository.dart';

class RelationshipServices {
  const RelationshipServices({required this.repository});

  final RelationshipRepository repository;
}

RelationshipServices createRelationshipServices({
  AppConfig? config,
  BackendCallable? backend,
  RelationshipRepository? repository,
}) {
  if (repository != null) {
    return RelationshipServices(repository: repository);
  }
  const mockOnly = bool.fromEnvironment('USE_MOCK_RELATIONSHIP');
  if (mockOnly) {
    return RelationshipServices(
      repository: RelationshipRepositoryImpl(
        dataSource: MockRelationshipDataSource(),
      ),
    );
  }
  return RelationshipServices(
    repository: RelationshipRepositoryImpl(
      dataSource: FunctionsRelationshipDataSource(
        backend:
            backend ??
            FirebaseFunctionsCallable(
              region: config?.functionsRegion ?? 'europe-west1',
            ),
      ),
    ),
  );
}
