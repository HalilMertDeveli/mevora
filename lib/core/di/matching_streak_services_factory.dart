import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/features/matching_streak/data/datasources/firebase_matching_streak_data_source.dart';
import 'package:mevora/features/matching_streak/data/repositories/matching_streak_repository_impl.dart';
import 'package:mevora/features/matching_streak/domain/repositories/matching_streak_repository.dart';

class MatchingStreakServices {
  const MatchingStreakServices({required this.repository});

  final MatchingStreakRepository repository;
}

MatchingStreakServices createMatchingStreakServices({
  AppConfig? config,
  BackendCallable? backend,
  MatchingStreakRepository? repository,
}) {
  if (repository != null) {
    return MatchingStreakServices(repository: repository);
  }
  final source = FirebaseMatchingStreakDataSource(
    backend:
        backend ??
        FirebaseFunctionsCallable(
          region: config?.functionsRegion ?? 'europe-west1',
        ),
  );
  return MatchingStreakServices(
    repository: MatchingStreakRepositoryImpl(source),
  );
}
