import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/core/identity/firebase_auth_uid_source.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/features/match_score/data/datasources/firebase_match_score_data_source.dart';
import 'package:mevora/features/match_score/data/datasources/match_score_data_source.dart';
import 'package:mevora/features/match_score/data/datasources/memory_match_score_data_source.dart';
import 'package:mevora/features/match_score/data/repositories/match_score_repository_impl.dart';
import 'package:mevora/features/match_score/domain/repositories/match_score_repository.dart';

class MatchScoreServices {
  const MatchScoreServices({required this.repository});

  final MatchScoreRepository repository;
}

MatchScoreServices createMatchScoreServices({
  AppConfig? config,
  BackendCallable? backend,
  AuthUidSource? uidSource,
  MatchScoreDataSource? dataSource,
  MatchScoreRepository? repository,
}) {
  final uid = uidSource ?? FirebaseAuthUidSource();
  if (repository != null) {
    return MatchScoreServices(repository: repository);
  }
  const mockOnly = bool.fromEnvironment('USE_MOCK_MATCH_SCORE');
  final source = dataSource ??
      (mockOnly
          ? MemoryMatchScoreDataSource()
          : FirebaseMatchScoreDataSource(
              backend: backend ??
                  FirebaseFunctionsCallable(
                    region: config?.functionsRegion ?? 'europe-west1',
                  ),
            ));
  return MatchScoreServices(
    repository: MatchScoreRepositoryImpl(dataSource: source, uidSource: uid),
  );
}
