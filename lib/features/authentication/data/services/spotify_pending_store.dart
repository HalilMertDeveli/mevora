enum SpotifyOAuthPurpose { login, musicLink }

/// Persists the Spotify PKCE verifier so auth can survive the OAuth callback.
class SpotifyPendingAuth {
  const SpotifyPendingAuth({
    required this.state,
    required this.verifier,
    required this.linkToCurrentUser,
    this.purpose = SpotifyOAuthPurpose.login,
  });

  final String state;
  final String verifier;
  final bool linkToCurrentUser;
  final SpotifyOAuthPurpose purpose;
}

abstract class SpotifyPendingStore {
  Future<void> save(SpotifyPendingAuth pending);

  Future<SpotifyPendingAuth?> read();

  Future<void> clear();
}

class MemorySpotifyPendingStore implements SpotifyPendingStore {
  SpotifyPendingAuth? _pending;

  @override
  Future<void> save(SpotifyPendingAuth pending) async {
    _pending = pending;
  }

  @override
  Future<SpotifyPendingAuth?> read() async => _pending;

  @override
  Future<void> clear() async {
    _pending = null;
  }
}

/// Process-wide store so a rebuilt service can finish a callback in the same
/// isolate. The PKCE verifier never leaves the device.
class StaticSpotifyPendingStore implements SpotifyPendingStore {
  static SpotifyPendingAuth? _pending;

  @override
  Future<void> save(SpotifyPendingAuth pending) async {
    _pending = pending;
  }

  @override
  Future<SpotifyPendingAuth?> read() async => _pending;

  @override
  Future<void> clear() async {
    _pending = null;
  }
}
