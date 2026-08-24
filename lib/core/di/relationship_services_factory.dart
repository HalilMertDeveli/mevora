import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/features/profile/data/datasources/firebase_profile_question_answer_data_source.dart';
import 'package:mevora/features/profile/data/datasources/memory_profile_question_answer_data_source.dart';
import 'package:mevora/features/profile/data/repositories/profile_question_answer_repository_impl.dart';
import 'package:mevora/features/profile/domain/repositories/profile_question_answer_repository.dart';
import 'package:mevora/features/relationship/data/datasources/functions_relationship_data_source.dart';
import 'package:mevora/features/relationship/data/datasources/mock_relationship_data_source.dart';
import 'package:mevora/features/relationship/data/repositories/relationship_repository_impl.dart';
import 'package:mevora/features/relationship/domain/repositories/relationship_repository.dart';

class RelationshipServices {
  const RelationshipServices({
    required this.repository,
    required this.profileAnswers,
  });

  final RelationshipRepository repository;
  final ProfileQuestionAnswerRepository profileAnswers;
}

RelationshipServices createRelationshipServices({
  AppConfig? config,
  BackendCallable? backend,
  RelationshipRepository? repository,
  ProfileQuestionAnswerRepository? profileAnswers,
}) {
  if (repository != null && profileAnswers != null) {
    return RelationshipServices(
      repository: repository,
      profileAnswers: profileAnswers,
    );
  }
  const mockOnly = bool.fromEnvironment('USE_MOCK_RELATIONSHIP');
  if (mockOnly) {
    return RelationshipServices(
      repository: RelationshipRepositoryImpl(
        dataSource: MockRelationshipDataSource(),
      ),
      profileAnswers: ProfileQuestionAnswerRepositoryImpl(
        dataSource: MemoryProfileQuestionAnswerDataSource(),
      ),
    );
  }
  final callable =
      backend ??
      FirebaseFunctionsCallable(
        region: config?.functionsRegion ?? 'europe-west1',
      );
  return RelationshipServices(
    repository: RelationshipRepositoryImpl(
      dataSource: FunctionsRelationshipDataSource(backend: callable),
    ),
    profileAnswers: ProfileQuestionAnswerRepositoryImpl(
      dataSource: FirebaseProfileQuestionAnswerDataSource(backend: callable),
    ),
  );
}
