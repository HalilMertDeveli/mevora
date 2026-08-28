import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/features/compatibility/data/repositories/why_you_matched_repository_impl.dart';
import 'package:mevora/features/compatibility/data/why_you_matched/why_you_matched_remote_data_source.dart';
import 'package:mevora/features/compatibility/domain/repositories/why_you_matched_repository.dart';

class CompatibilityServices {
  const CompatibilityServices({required this.whyYouMatchedRepository});

  final WhyYouMatchedRepository whyYouMatchedRepository;
}

CompatibilityServices createCompatibilityServices({
  AppConfig? config,
  BackendCallable? backend,
  WhyYouMatchedRepository? whyYouMatchedRepository,
}) {
  if (whyYouMatchedRepository != null) {
    return CompatibilityServices(
      whyYouMatchedRepository: whyYouMatchedRepository,
    );
  }
  final callable = backend ??
      FirebaseFunctionsCallable(
        region: config?.functionsRegion ?? 'europe-west1',
      );
  final remote = WhyYouMatchedRemoteDataSource(backend: callable);
  return CompatibilityServices(
    whyYouMatchedRepository: WhyYouMatchedRepositoryImpl(remote: remote),
  );
}
