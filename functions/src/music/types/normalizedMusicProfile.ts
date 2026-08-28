/** Provider identifiers. External APIs register new values without schema breaks. */
export type MusicProviderId = "spotify" | (string & {});

export type RecentArtistItem = {
  id: string;
  name: string;
  image?: string | null;
};

export type GenreShareItem = {
  name: string;
  percent: number;
};

export type NormalizedTrackItem = {
  id: string;
  name: string;
  artist?: string;
  image?: string | null;
  playedAt?: string;
  genres?: string[];
};

export type NormalizedArtistItem = {
  id: string;
  name: string;
  image?: string | null;
  genres?: string[];
};

export type NormalizedPlaylistItem = {
  id: string;
  name: string;
  trackCount: number;
};

/**
 * Canonical music taste contract consumed by Firestore persistence and
 * the existing compatibility engine. No OAuth tokens belong here.
 */
export type NormalizedMusicProfile = {
  provider: MusicProviderId;
  connected: boolean;
  providerUserId: string;
  displayName: string | null;
  trackIds: string[];
  artistIds: string[];
  recentTrackIds: string[];
  recentArtistIds: string[];
  recentArtists: RecentArtistItem[];
  topTracks: NormalizedTrackItem[];
  topArtists: NormalizedArtistItem[];
  /** Last N unique recently-played tracks (display). */
  recentlyPlayed: NormalizedTrackItem[];
  topGenres: GenreShareItem[];
  playlistTrackIds: string[];
  playlists: NormalizedPlaylistItem[];
};
