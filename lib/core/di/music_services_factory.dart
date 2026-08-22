import 'package:mevora/core/config/app_config.dart';
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
  const mockOnly = bool.fromEnvironment('USE_MOCK_MUSIC');
  if (mockOnly || spotifyAuthService == null) {
    return MusicServices(
      repository: MusicRepositoryImpl(dataSource: MockMusicDataSource()),
    );
  }
  return MusicServices(
    repository: MusicRepositoryImpl(
      dataSource: FunctionsMusicDataSource(
        backend: backend ??
            FirebaseFunctionsCallable(
              region: config?.functionsRegion ?? 'europe-west1',
            ),
        connectSpotifyImpl: spotifyAuthService.linkMusicAccount,
      ),
    ),
  );
}
