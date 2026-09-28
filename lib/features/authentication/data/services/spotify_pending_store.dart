enum SpotifyOAuthPurpose { login, musicLink }

/// Persists the Spotify PKCE verifier so auth can survive the OAuth callback.
///
/// The record carries its own expiry. This store outlives the screen that
/// started the flow, so without one a verifier and state abandoned at the
/// timeout would stay honourable for the rest of the process and let a late
/// callback finish an exchange nobody is waiting for any more.
class SpotifyPendingAuth {
  const SpotifyPendingAuth({
    required this.state,
    required this.verifier,
    required this.linkToCurrentUser,
    required this.expiresAt,
    this.purpose = SpotifyOAuthPurpose.login,
  });

  final String state;
  final String verifier;
  final bool linkToCurrentUser;
  final SpotifyOAuthPurpose purpose;

  /// UTC instant from which this record must no longer be honoured.
  final DateTime expiresAt;

  bool hasExpired(DateTime now) => !now.toUtc().isBefore(expiresAt);
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
