/// Client-visible connection status. Refresh tokens never appear here.
class ConnectedMusicAccount {
  const ConnectedMusicAccount({
    required this.connected,
    this.displayName,
    this.spotifyUserId,
    this.connectedAt,
    this.lastSyncedAt,
  });

  final bool connected;
  final String? displayName;
  final String? spotifyUserId;
  final DateTime? connectedAt;
  final DateTime? lastSyncedAt;

  static const disconnected = ConnectedMusicAccount(connected: false);
}
