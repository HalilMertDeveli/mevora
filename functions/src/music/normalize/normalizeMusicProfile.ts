import type {DocumentData} from "firebase-admin/firestore";
import {
  MUSIC_PROFILE_VERSION,
  RECENT_UNIQUE_ARTIST_DISPLAY_LIMIT,
  RECENT_UNIQUE_TRACK_LIMIT,
  type MusicTaste,
} from "../../musicCompatibility.js";
import type {
  GenreShareItem,
  NormalizedArtistItem,
  NormalizedMusicProfile,
  NormalizedTrackItem,
  RecentArtistItem,
} from "../types/normalizedMusicProfile.js";

export const SPOTIFY_PROVIDER_ID = "spotify";

function asStringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is string => typeof item === "string" && item.trim().length > 0);
}

type RawRecentlyPlayedItem = {
  track?: DocumentData;
  played_at?: string;
};

type RawArtistRef = {
  id?: string;
  name?: string;
  images?: Array<{url?: string}>;
};

/**
 * Chronological unique recent artists (max 5) from recently-played payload.
 * Preserves Spotify play order; skips duplicate artist IDs.
 */
export function extractRecentArtists(
  items: RawRecentlyPlayedItem[],
  limit = RECENT_UNIQUE_ARTIST_DISPLAY_LIMIT,
): RecentArtistItem[] {
  const out: RecentArtistItem[] = [];
  const seen = new Set<string>();
  for (const item of items) {
    const track = (item.track ?? {}) as DocumentData;
    const artists = Array.isArray(track.artists) ? track.artists as RawArtistRef[] : [];
    for (const artist of artists) {
      const id = typeof artist.id === "string" ? artist.id.trim() : "";
      const name = typeof artist.name === "string" ? artist.name.trim() : "";
      if (!id || !name || seen.has(id)) continue;
      seen.add(id);
      const image = artist.images?.find((row) => typeof row.url === "string" && row.url)?.url ?? null;
      out.push({id, name, image});
      if (out.length >= limit) return out;
    }
  }
  return out;
}

/** Existing compatibility signal: up to 30 unique artist IDs from recently-played. */
export function extractRecentArtistIds(items: RawRecentlyPlayedItem[], limit = 30): string[] {
  return [...new Set(
    items.flatMap((item) => {
      const track = (item.track ?? {}) as DocumentData;
      const list = Array.isArray(track.artists) ? track.artists : [];
      return list
        .map((artist: DocumentData) => String(artist.id ?? ""))
        .filter(Boolean);
    }),
  )].slice(0, limit);
}

export function summarizeTracks(
  items: Array<DocumentData>,
  limit = 20,
): NormalizedTrackItem[] {
  const out: NormalizedTrackItem[] = [];
  const seen = new Set<string>();
  for (const item of items) {
    const track = (item.track ?? item) as DocumentData;
    const id = typeof track.id === "string" ? track.id : "";
    if (!id || seen.has(id)) continue;
    seen.add(id);
    const artists = Array.isArray(track.artists)
      ? track.artists.map((artist: DocumentData) => String(artist.name ?? "")).filter(Boolean)
      : [];
    const playedAt = typeof item.played_at === "string" ? item.played_at : undefined;
    const image = (track.album as DocumentData | undefined)?.images as Array<{url?: string}> | undefined;
    const albumImage = image?.find((row) => typeof row.url === "string" && row.url)?.url ?? null;
    out.push({
      id,
      name: String(track.name ?? ""),
      artist: artists.join(", "),
      image: albumImage,
      ...(playedAt ? {playedAt} : {}),
    });
    if (out.length >= limit) break;
  }
  return out;
}

export function summarizeArtists(
  items: Array<DocumentData>,
  limit = 20,
): NormalizedArtistItem[] {
  const out: NormalizedArtistItem[] = [];
  for (const item of items) {
    const id = typeof item.id === "string" ? item.id : "";
    if (!id) continue;
    const image = (item.images as Array<{url?: string}> | undefined)
      ?.find((row) => typeof row.url === "string" && row.url)?.url ?? null;
    out.push({
      id,
      name: String(item.name ?? ""),
      image,
      genres: asStringList(item.genres),
    });
    if (out.length >= limit) break;
  }
  return out;
}

export function genreShares(artists: NormalizedArtistItem[]): GenreShareItem[] {
  const counts = new Map<string, number>();
  for (const artist of artists) {
    for (const genre of artist.genres ?? []) {
      const key = genre.trim().toLowerCase();
      if (!key) continue;
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }
  }
  const total = [...counts.values()].reduce((sum, value) => sum + value, 0);
  if (total === 0) return [];
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 8)
    .map(([name, count]) => ({
      name,
      percent: Math.max(1, Math.round((count / total) * 100)),
    }));
}

/** Build normalized profile from Spotify API payloads (no network I/O). */
export function buildSpotifyNormalizedProfile(input: {
  providerUserId: string;
  displayName: string | null;
  topTracksRaw: Array<DocumentData>;
  topArtistsRaw: Array<DocumentData>;
  recentlyPlayedRaw: RawRecentlyPlayedItem[];
  playlistTrackIds: string[];
  playlists: Array<{id: string; name: string; trackCount: number}>;
}): NormalizedMusicProfile {
  const topTracks = summarizeTracks(input.topTracksRaw);
  const topArtists = summarizeArtists(input.topArtistsRaw);
  const recentTracks = summarizeTracks(
    input.recentlyPlayedRaw as Array<DocumentData>,
    RECENT_UNIQUE_TRACK_LIMIT,
  );
  const topGenres = genreShares(topArtists);
  const recentArtists = extractRecentArtists(input.recentlyPlayedRaw);
  const recentArtistIds = extractRecentArtistIds(input.recentlyPlayedRaw);

  return {
    provider: SPOTIFY_PROVIDER_ID,
    connected: true,
    providerUserId: input.providerUserId,
    displayName: input.displayName,
    trackIds: topTracks.map((item) => item.id),
    artistIds: topArtists.map((item) => item.id),
    recentTrackIds: recentTracks.map((item) => item.id),
    recentArtistIds,
    recentArtists,
    topTracks,
    topArtists,
    recentlyPlayed: recentTracks,
    topGenres,
    playlistTrackIds: input.playlistTrackIds,
    playlists: input.playlists,
  };
}

/** Maps normalized profile to Firestore summary `musicProfile` + display arrays. */
export function normalizedToMusicProfile(normalized: NormalizedMusicProfile): DocumentData {
  return {
    genres: normalized.topGenres,
    genreNames: normalized.topGenres.map((item) => item.name),
    artistIds: normalized.artistIds,
    trackIds: normalized.trackIds,
    recentTrackIds: normalized.recentTrackIds,
    recentArtistIds: normalized.recentArtistIds,
    recentArtists: normalized.recentArtists,
    playlistTrackIds: normalized.playlistTrackIds,
    playlists: normalized.playlists,
    musicFingerprint: {
      version: MUSIC_PROFILE_VERSION,
      trackIds: normalized.trackIds,
      artistIds: normalized.artistIds,
      recentTrackIds: normalized.recentTrackIds,
      genreNames: normalized.topGenres.map((item) => item.name),
    },
  };
}

export function normalizedToSummaryFields(normalized: NormalizedMusicProfile): DocumentData {
  return {
    provider: normalized.provider,
    spotifyConnected: normalized.provider === SPOTIFY_PROVIDER_ID,
    spotifyUserId: normalized.providerUserId,
    displayName: normalized.displayName,
    topTracks: normalized.topTracks,
    topArtists: normalized.topArtists,
    recentlyPlayed: normalized.recentlyPlayed,
    playlists: normalized.playlists,
    musicProfile: normalizedToMusicProfile(normalized),
    musicProfileVersion: MUSIC_PROFILE_VERSION,
  };
}

/** Backward-compatible taste extraction for v2 and v3 summaries. */
export function tasteFromSummaryDocument(data: DocumentData | undefined): MusicTaste | null {
  if (!data) return null;
  const connected = data.spotifyConnected === true || data.connected === true;
  if (!connected) return null;
  const profile = (data.musicProfile ?? {}) as DocumentData;
  const genres = Array.isArray(profile.genres)
    ? profile.genres
      .map((item) => (item && typeof item === "object"
        ? String((item as {name?: string}).name ?? "")
        : String(item)))
      .filter((name) => name.length > 0)
    : asStringList(profile.genreNames);
  return {
    trackIds: asStringList(profile.trackIds),
    artistIds: asStringList(profile.artistIds),
    genres,
    recentTrackIds: asStringList(profile.recentTrackIds),
    recentArtistIds: asStringList(profile.recentArtistIds),
    playlistTrackIds: asStringList(profile.playlistTrackIds),
  };
}
