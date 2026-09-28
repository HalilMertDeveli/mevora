/// Display-only track or artist card. No audio URLs — this MVP never plays music.
class MusicTrack {
  const MusicTrack({
    required this.id,
    required this.name,
    this.artist = '',
    this.albumImage,
    this.genres = const [],
  });

  final String id;
  final String name;
  final String artist;
  final String? albumImage;
  final List<String> genres;
}

class MusicArtist {
  const MusicArtist({
    required this.id,
    required this.name,
    this.image,
    this.genres = const [],
  });

  final String id;
  final String name;
  final String? image;
  final List<String> genres;
}

class GenreShare {
  const GenreShare({required this.name, required this.percent});

  final String name;
  final int percent;
}

/// A Spotify playlist, as the Music Profile shows it.
///
/// Only what the screen needs: no track contents, and nothing that would say
/// what is inside a private playlist. The names stay on the owner's own Music
/// page and never reach another member's profile.
class MusicPlaylist {
  const MusicPlaylist({
    required this.id,
    required this.name,
    this.trackCount = 0,
  });

  final String id;
  final String name;
  final int trackCount;
}
