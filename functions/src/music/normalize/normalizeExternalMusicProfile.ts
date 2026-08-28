import {
  RECENT_UNIQUE_ARTIST_DISPLAY_LIMIT,
  RECENT_UNIQUE_TRACK_LIMIT,
} from "../../musicCompatibility.js";
import {EXTERNAL_PROVIDER_ID} from "../externalMusicConfig.js";
import {genreShares} from "./normalizeMusicProfile.js";
import type {
  GenreShareItem,
  NormalizedArtistItem,
  NormalizedMusicProfile,
  NormalizedTrackItem,
  RecentArtistItem,
} from "../types/normalizedMusicProfile.js";

/** Logical external API artist shape — mapped when API documentation arrives. */
export type ExternalMusicApiArtist = {
  id: string;
  name: string;
  image?: string | null;
  genres?: string[];
};

/** Logical external API track shape. */
export type ExternalMusicApiTrack = {
  id: string;
  name: string;
  artist?: string;
  image?: string | null;
};

/** Logical external API recent-play shape. */
export type ExternalMusicApiRecentPlay = {
  trackId: string;
  trackName?: string;
  artistId: string;
  artistName: string;
  artistImage?: string | null;
  playedAt?: string;
};

/** Explicit genre shares when the external API provides them directly. */
export type ExternalMusicApiGenre = {
  name: string;
  percent?: number;
};

/** Payload contract for normalizing external API taste responses (no network I/O). */
export type ExternalMusicApiTastePayload = {
  userId: string;
  displayName?: string | null;
  topTracks?: ExternalMusicApiTrack[];
  topArtists?: ExternalMusicApiArtist[];
  recentPlays?: ExternalMusicApiRecentPlay[];
  genres?: ExternalMusicApiGenre[];
  playlistTrackIds?: string[];
  playlists?: Array<{id: string; name: string; trackCount: number}>;
};

function asStringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is string => typeof item === "string" && item.trim().length > 0);
}

function summarizeExternalTracks(
  items: ExternalMusicApiTrack[],
  limit = 20,
): NormalizedTrackItem[] {
  const out: NormalizedTrackItem[] = [];
  const seen = new Set<string>();
  for (const item of items) {
    const id = item.id.trim();
    if (!id || seen.has(id)) continue;
    seen.add(id);
    out.push({
      id,
      name: item.name.trim(),
      artist: item.artist?.trim() || undefined,
      image: item.image ?? null,
    });
    if (out.length >= limit) break;
  }
  return out;
}

function summarizeExternalArtists(
  items: ExternalMusicApiArtist[],
  limit = 20,
): NormalizedArtistItem[] {
  const out: NormalizedArtistItem[] = [];
  for (const item of items) {
    const id = item.id.trim();
    if (!id) continue;
    out.push({
      id,
      name: item.name.trim(),
      image: item.image ?? null,
      genres: asStringList(item.genres),
    });
    if (out.length >= limit) break;
  }
  return out;
}

/** Chronological unique recent artists (max 5) from external recent-play payload. */
export function extractExternalRecentArtists(
  plays: ExternalMusicApiRecentPlay[],
  limit = RECENT_UNIQUE_ARTIST_DISPLAY_LIMIT,
): RecentArtistItem[] {
  const out: RecentArtistItem[] = [];
  const seen = new Set<string>();
  for (const play of plays) {
    const id = play.artistId.trim();
    const name = play.artistName.trim();
    if (!id || !name || seen.has(id)) continue;
    seen.add(id);
    out.push({
      id,
      name,
      image: play.artistImage ?? null,
    });
    if (out.length >= limit) return out;
  }
  return out;
}

/** Up to 30 unique artist IDs from external recent plays (compatibility signal). */
export function extractExternalRecentArtistIds(
  plays: ExternalMusicApiRecentPlay[],
  limit = 30,
): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  for (const play of plays) {
    const id = play.artistId.trim();
    if (!id || seen.has(id)) continue;
    seen.add(id);
    out.push(id);
    if (out.length >= limit) break;
  }
  return out;
}

function summarizeExternalRecentTracks(
  plays: ExternalMusicApiRecentPlay[],
  limit = RECENT_UNIQUE_TRACK_LIMIT,
): NormalizedTrackItem[] {
  const out: NormalizedTrackItem[] = [];
  const seen = new Set<string>();
  for (const play of plays) {
    const id = play.trackId.trim();
    if (!id || seen.has(id)) continue;
    seen.add(id);
    out.push({
      id,
      name: play.trackName?.trim() || id,
      artist: play.artistName.trim() || undefined,
      image: null,
      ...(play.playedAt ? {playedAt: play.playedAt} : {}),
    });
    if (out.length >= limit) break;
  }
  return out;
}

function normalizeExternalGenres(
  explicit: ExternalMusicApiGenre[] | undefined,
  topArtists: NormalizedArtistItem[],
): GenreShareItem[] {
  if (explicit && explicit.length > 0) {
    return explicit
      .filter((item) => typeof item.name === "string" && item.name.trim().length > 0)
      .slice(0, 8)
      .map((item) => ({
        name: item.name.trim(),
        percent: typeof item.percent === "number" && item.percent > 0
          ? Math.round(item.percent)
          : 1,
      }));
  }
  return genreShares(topArtists);
}

/** Build normalized profile from external API payload (no network I/O). */
export function buildExternalNormalizedProfile(
  payload: ExternalMusicApiTastePayload,
): NormalizedMusicProfile {
  const topTracks = summarizeExternalTracks(payload.topTracks ?? []);
  const topArtists = summarizeExternalArtists(payload.topArtists ?? []);
  const recentPlays = payload.recentPlays ?? [];
  const recentTracks = summarizeExternalRecentTracks(recentPlays);
  const recentArtists = extractExternalRecentArtists(recentPlays);
  const recentArtistIds = extractExternalRecentArtistIds(recentPlays);
  const topGenres = normalizeExternalGenres(payload.genres, topArtists);

  return {
    provider: EXTERNAL_PROVIDER_ID,
    connected: true,
    providerUserId: payload.userId.trim(),
    displayName: payload.displayName ?? null,
    trackIds: topTracks.map((item) => item.id),
    artistIds: topArtists.map((item) => item.id),
    recentTrackIds: recentTracks.map((item) => item.id),
    recentArtistIds,
    recentArtists,
    topTracks,
    topArtists,
    recentlyPlayed: recentTracks,
    topGenres,
    playlistTrackIds: (payload.playlistTrackIds ?? []).slice(0, 200),
    playlists: (payload.playlists ?? []).slice(0, 10),
  };
}
