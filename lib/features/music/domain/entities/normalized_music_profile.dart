import 'package:mevora/features/music/domain/entities/music_track.dart';

/// Display-ready recent artist from normalized music profile (max 5 unique).
class RecentArtist {
  const RecentArtist({
    required this.id,
    required this.name,
    this.image,
  });

  final String id;
  final String name;
  final String? image;
}

/// Canonical normalized music profile fields exposed to the client.
/// Never includes OAuth tokens or secrets.
class NormalizedMusicProfileView {
  const NormalizedMusicProfileView({
    this.provider,
    this.recentArtists = const [],
    this.topGenres = const [],
  });

  final String? provider;
  final List<RecentArtist> recentArtists;
  final List<GenreShare> topGenres;
}
