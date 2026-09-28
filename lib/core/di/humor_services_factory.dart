import 'package:flutter/foundation.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
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

/// Raw `--dart-define=USE_MOCK_HUMOR=...` value; empty when it is not passed.
const String _useMockHumorDefine = String.fromEnvironment('USE_MOCK_HUMOR');

/// Whether Humor runs on the in-memory [MockHumorDataSource] instead of the
/// real backend.
///
/// The mock is strictly opt-in for local UI work: it is used only when
/// [define] is exactly `'true'` (`--dart-define=USE_MOCK_HUMOR=true`), the
/// [environment] is development and the build is not a release build. Every
/// other case — define unset or any other value, staging, production, any
/// release build — returns false, so Humor calls Cloud Functions (the
/// Functions emulator when `USE_EMULATORS=true`) and its state stays
/// server-authoritative.
bool resolveUseMockHumor({
  required String define,
  required AppEnvironment environment,
  bool releaseMode = kReleaseMode,
}) {
  return define == 'true' && environment.isDevelopment && !releaseMode;
}

/// Builds the Humor services on the real backend by default.
///
/// An injected [repository] (tests) always wins. Otherwise Humor uses
/// [FunctionsHumorDataSource] over [backend], or over Cloud Functions in
/// [AppConfig.functionsRegion], unless [resolveUseMockHumor] opts a
/// development build into the mock. A missing [config] counts as production,
/// so it can never select the mock.
HumorServices createHumorServices({
  AppConfig? config,
  BackendCallable? backend,
  HumorRepository? repository,
  @visibleForTesting String useMockHumorDefine = _useMockHumorDefine,
}) {
  if (repository != null) {
    return HumorServices(repository: repository);
  }
  final useMock = resolveUseMockHumor(
    define: useMockHumorDefine,
    environment: config?.environment ?? AppEnvironment.production,
  );
  if (useMock) {
    debugPrint(
      'Humor: USE_MOCK_HUMOR=true, using the in-memory mock '
      '(no Cloud Functions calls, nothing persists).',
    );
    return HumorServices(
      repository: HumorRepositoryImpl(dataSource: MockHumorDataSource()),
    );
  }
  return HumorServices(
    repository: HumorRepositoryImpl(
      dataSource: FunctionsHumorDataSource(
        backend:
            backend ??
            FirebaseFunctionsCallable(
              region: config?.functionsRegion ?? 'europe-west1',
            ),
      ),
    ),
  );
}
