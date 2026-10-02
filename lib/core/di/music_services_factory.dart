import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/build_guards.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/features/authentication/data/services/spotify_auth_service.dart';
import 'package:mevora/features/music/data/datasources/functions_music_data_source.dart';
import 'package:mevora/features/music/data/datasources/mock_music_data_source.dart';
import 'package:mevora/features/music/data/repositories/music_repository_impl.dart';
import 'package:mevora/features/music/domain/repositories/music_repository.dart';

class MusicServices {
  const MusicServices({required this.repository});

  final MusicRepository repository;
}

MusicServices createMusicServices({
  AppConfig? config,
  BackendCallable? backend,
  SpotifyAuthService? spotifyAuthService,
  MusicRepository? repository,
}) {
  if (repository != null) {
    return MusicServices(repository: repository);
  }
  final mockOnly = mockDataSourceAllowed(
    define: const bool.fromEnvironment('USE_MOCK_MUSIC'),
    environment: config?.environment,
  );
  if (mockOnly) {
    return MusicServices(
      repository: MusicRepositoryImpl(dataSource: MockMusicDataSource()),
    );
  }
  // Falling back to the mock because a dependency happened to be missing is
  // how a build ends up quietly showing invented music to a real member. An
  // assert said so in debug only; in a release build the fallback was silent.
  // There is no fallback now: the wiring is wrong, and that is an error.
  if (spotifyAuthService == null) {
    throw StateError(
      'createMusicServices needs a SpotifyAuthService unless USE_MOCK_MUSIC '
      'is set in a development build.',
    );
  }
  return MusicServices(
    repository: MusicRepositoryImpl(
      dataSource: FunctionsMusicDataSource(
        backend:
            backend ??
            FirebaseFunctionsCallable(
              region: config?.functionsRegion ?? 'europe-west1',
            ),
        connectSpotifyImpl: spotifyAuthService.linkMusicAccount,
      ),
    ),
  );
}
