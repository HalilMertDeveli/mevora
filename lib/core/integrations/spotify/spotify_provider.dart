import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';

/// Spotify OAuth adapter. The client secret never ships in the app.
abstract class SpotifyProvider {
  Future<Result<void>> connect();
}

class UnavailableSpotifyProvider implements SpotifyProvider {
  const UnavailableSpotifyProvider();

  @override
  Future<Result<void>> connect() async {
    return const Err(
      PermissionFailure('Spotify is not available'),
    );
  }
}
