export const MUSIC_SCOPES =
  "user-top-read user-read-recently-played playlist-read-private";
export const SYNC_MIN_INTERVAL_MS = 6 * 60 * 60 * 1000;
export const MUSIC_RANKING_WEIGHT = 0.15;
export const MUSIC_PROFILE_VERSION = 2;
/** MVP: last N unique recently-played Spotify track IDs (deduped by track id). */
export const RECENT_UNIQUE_TRACK_LIMIT = 10;

/** Default weights when playlist overlap data is unavailable. */
export const MUSIC_WEIGHTS_BASE = {
  tracks: 0.4,
  artists: 0.3,
  genres: 0.2,
  recent: 0.1,
  playlist: 0,
} as const;

/** Weights when both users have playlist track IDs from Spotify. */
export const MUSIC_WEIGHTS_WITH_PLAYLIST = {
  tracks: 0.35,
  artists: 0.25,
  genres: 0.2,
  playlist: 0.1,
  recent: 0.1,
} as const;

export type MusicTaste = {
  trackIds: string[];
  artistIds: string[];
  genres: string[];
  recentTrackIds: string[];
  recentArtistIds: string[];
  /** Minimized playlist track IDs only — never fabricated play counts. */
  playlistTrackIds?: string[];
};

export type MusicCompatibilityBreakdown = {
  tracks: number;
  artists: number;
  genres: number;
  recent: number;
  playlist: number;
};

export type MusicInsightCode =
  | "band_very_high"
  | "band_high"
  | "band_mid"
  | "band_low"
  | "shared_tracks"
  | "shared_artists"
  | "shared_playlist_tracks"
  | "shared_recent_tracks"
  | "top_shared_artist"
  | "top_shared_genres"
  | "data_unavailable";

export type MusicInsight = {
  code: MusicInsightCode;
  /** Optional display params (names / counts). Never fake listening stats. */
  params?: Record<string, string | number>;
};

export type MusicCompatibility = {
  score: number;
  sharedTracks: string[];
  sharedArtists: string[];
  sharedGenres: string[];
  sharedRecentTracks: string[];
  sharedPlaylistTracks: string[];
  breakdown: MusicCompatibilityBreakdown;
  insights: MusicInsight[];
};

export function isTasteEmpty(taste: MusicTaste | null | undefined): boolean {
  if (!taste) return true;
  return (
    taste.trackIds.length === 0 &&
    taste.artistIds.length === 0 &&
    taste.genres.length === 0 &&
    taste.recentTrackIds.length === 0 &&
    taste.recentArtistIds.length === 0 &&
    (taste.playlistTrackIds?.length ?? 0) === 0
  );
}

function norm(value: string): string {
  return value.trim().toLowerCase();
}

function intersect(a: string[], b: string[]): string[] {
  const other = new Set(b.map(norm).filter((item) => item.length > 0));
  const seen = new Set<string>();
  const out: string[] = [];
  for (const item of a) {
    const key = norm(item);
    if (!key || !other.has(key) || seen.has(key)) continue;
    seen.add(key);
    out.push(item.trim());
  }
  return out;
}

function overlap(a: string[], b: string[]): number {
  if (!a.length || !b.length) return 0;
  const shared = intersect(a, b).length;
  const denom = Math.min(a.length, b.length);
  return denom === 0 ? 0 : Math.min(1, shared / denom);
}

function recentOverlap(viewer: MusicTaste, candidate: MusicTaste): {
  ratio: number;
  sharedTracks: string[];
  sharedArtists: string[];
} {
  const sharedTracks = intersect(viewer.recentTrackIds, candidate.recentTrackIds);
  const sharedArtists = intersect(viewer.recentArtistIds, candidate.recentArtistIds);
  const viewerRecent = viewer.recentTrackIds.length + viewer.recentArtistIds.length;
  const candidateRecent = candidate.recentTrackIds.length + candidate.recentArtistIds.length;
  const denom = Math.min(viewerRecent, candidateRecent);
  const ratio = denom <= 0
    ? 0
    : Math.min(1, (sharedTracks.length + sharedArtists.length) / denom);
  return {ratio, sharedTracks, sharedArtists};
}

function musicBand(score: number): MusicInsightCode {
  if (score >= 85) return "band_very_high";
  if (score >= 70) return "band_high";
  if (score >= 40) return "band_mid";
  return "band_low";
}

export function buildMusicInsights(input: {
  score: number;
  sharedTracks: string[];
  sharedArtists: string[];
  sharedGenres: string[];
  sharedRecentTracks: string[];
  sharedPlaylistTracks: string[];
  /** Display names when resolved; otherwise IDs may appear. */
  trackNames?: string[];
  artistNames?: string[];
}): MusicInsight[] {
  const insights: MusicInsight[] = [{code: musicBand(input.score)}];
  if (input.sharedTracks.length > 0) {
    insights.push({
      code: "shared_tracks",
      params: {count: input.sharedTracks.length},
    });
  }
  if (input.sharedArtists.length > 0) {
    insights.push({
      code: "shared_artists",
      params: {count: input.sharedArtists.length},
    });
  }
  if (input.sharedPlaylistTracks.length > 0) {
    insights.push({
      code: "shared_playlist_tracks",
      params: {count: input.sharedPlaylistTracks.length},
    });
  }
  if (input.sharedRecentTracks.length > 0) {
    insights.push({
      code: "shared_recent_tracks",
      params: {count: input.sharedRecentTracks.length},
    });
  }
  const topArtist = (input.artistNames ?? input.sharedArtists)[0];
  if (topArtist) {
    insights.push({
      code: "top_shared_artist",
      params: {name: topArtist},
    });
  }
  if (input.sharedGenres.length > 0) {
    const genres = input.sharedGenres.slice(0, 2).join(", ");
    insights.push({
      code: "top_shared_genres",
      params: {genres},
    });
  }
  if (
    input.sharedTracks.length === 0 &&
    input.sharedArtists.length === 0 &&
    input.sharedGenres.length === 0 &&
    input.sharedPlaylistTracks.length === 0 &&
    input.sharedRecentTracks.length === 0
  ) {
    insights.push({code: "data_unavailable"});
  }
  return insights;
}

export function scoreMusicCompatibility(
  viewer: MusicTaste,
  candidate: MusicTaste,
): MusicCompatibility {
  if (isTasteEmpty(viewer) || isTasteEmpty(candidate)) {
    return {
      score: 0,
      sharedTracks: [],
      sharedArtists: [],
      sharedGenres: [],
      sharedRecentTracks: [],
      sharedPlaylistTracks: [],
      breakdown: {tracks: 0, artists: 0, genres: 0, recent: 0, playlist: 0},
      insights: [{code: "data_unavailable"}],
    };
  }

  const sharedTracks = intersect(viewer.trackIds, candidate.trackIds);
  const sharedArtists = intersect(viewer.artistIds, candidate.artistIds);
  const sharedGenres = intersect(viewer.genres, candidate.genres);
  const recent = recentOverlap(viewer, candidate);
  const viewerPlaylist = viewer.playlistTrackIds ?? [];
  const candidatePlaylist = candidate.playlistTrackIds ?? [];
  const hasPlaylistSignal = viewerPlaylist.length > 0 && candidatePlaylist.length > 0;
  const sharedPlaylistTracks = hasPlaylistSignal
    ? intersect(viewerPlaylist, candidatePlaylist)
    : [];

  const trackRatio = overlap(viewer.trackIds, candidate.trackIds);
  const artistRatio = overlap(viewer.artistIds, candidate.artistIds);
  const genreRatio = overlap(viewer.genres, candidate.genres);
  const playlistRatio = hasPlaylistSignal
    ? overlap(viewerPlaylist, candidatePlaylist)
    : 0;

  const weights = hasPlaylistSignal ? MUSIC_WEIGHTS_WITH_PLAYLIST : MUSIC_WEIGHTS_BASE;
  const weighted =
    trackRatio * weights.tracks +
    artistRatio * weights.artists +
    genreRatio * weights.genres +
    recent.ratio * weights.recent +
    playlistRatio * weights.playlist;

  const score = Math.max(0, Math.min(100, Math.round(weighted * 100)));
  const breakdown: MusicCompatibilityBreakdown = {
    tracks: Math.round(trackRatio * 100),
    artists: Math.round(artistRatio * 100),
    genres: Math.round(genreRatio * 100),
    recent: Math.round(recent.ratio * 100),
    playlist: Math.round(playlistRatio * 100),
  };

  return {
    score,
    sharedTracks,
    sharedArtists,
    sharedGenres,
    sharedRecentTracks: recent.sharedTracks,
    sharedPlaylistTracks,
    breakdown,
    insights: buildMusicInsights({
      score,
      sharedTracks,
      sharedArtists,
      sharedGenres,
      sharedRecentTracks: recent.sharedTracks,
      sharedPlaylistTracks,
    }),
  };
}

export function musicRankingBonus(score: number): number {
  if (score <= 0) return 0;
  return Math.max(0, Math.min(15, Math.round(score * MUSIC_RANKING_WEIGHT)));
}

export function interestedInAllows(interestedIn: unknown, gender: unknown): boolean {
  const raw = typeof interestedIn === "string" ? interestedIn.trim().toLowerCase() : "";
  if (!raw || raw === "everyone") return true;
  // Settings UI may store singular preferredGender ("man"/"woman").
  const want =
    raw === "man" || raw === "male" || raw === "men"
      ? "men"
      : raw === "woman" || raw === "female" || raw === "women"
        ? "women"
        : raw;
  const g = typeof gender === "string" ? gender.trim().toLowerCase() : "";
  if (!g) return true;
  if (want === "men") return g === "man" || g === "male" || g === "men";
  if (want === "women") return g === "woman" || g === "female" || g === "women";
  return true;
}

export function isoWeekId(date = new Date()): string {
  const utc = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  const day = utc.getUTCDay() || 7;
  utc.setUTCDate(utc.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(utc.getUTCFullYear(), 0, 1));
  const week = Math.ceil(((utc.getTime() - yearStart.getTime()) / 86400000 + 1) / 7);
  return `${utc.getUTCFullYear()}-W${String(week).padStart(2, "0")}`;
}

export type NamedMusicItem = {id: string; name: string; artist?: string};

/** Resolve Spotify IDs to display names from both profiles' cached metadata. */
export function resolveMusicNames(
  ids: string[],
  catalogs: NamedMusicItem[],
): string[] {
  const byId = new Map<string, string>();
  for (const item of catalogs) {
    if (!item.id || !item.name) continue;
    byId.set(item.id, item.name);
  }
  const out: string[] = [];
  const seen = new Set<string>();
  for (const id of ids) {
    const name = byId.get(id) ?? "";
    if (!name || seen.has(norm(name))) continue;
    seen.add(norm(name));
    out.push(name);
  }
  return out;
}

export function enrichMusicCompatibility(
  result: MusicCompatibility,
  catalogs: NamedMusicItem[],
): MusicCompatibility & {
  sharedTrackNames: string[];
  sharedArtistNames: string[];
} {
  const sharedTrackNames = resolveMusicNames(result.sharedTracks, catalogs);
  const sharedArtistNames = resolveMusicNames(result.sharedArtists, catalogs);
  return {
    ...result,
    sharedTrackNames,
    sharedArtistNames,
    insights: buildMusicInsights({
      score: result.score,
      sharedTracks: result.sharedTracks,
      sharedArtists: result.sharedArtists,
      sharedGenres: result.sharedGenres,
      sharedRecentTracks: result.sharedRecentTracks,
      sharedPlaylistTracks: result.sharedPlaylistTracks,
      trackNames: sharedTrackNames,
      artistNames: sharedArtistNames,
    }),
  };
}
