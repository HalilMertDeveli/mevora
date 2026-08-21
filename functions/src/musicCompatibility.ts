export const MUSIC_SCOPES = "user-top-read user-read-recently-played";
export const SYNC_MIN_INTERVAL_MS = 6 * 60 * 60 * 1000;
export const MUSIC_RANKING_WEIGHT = 0.15;

export type MusicTaste = {
  trackIds: string[];
  artistIds: string[];
  genres: string[];
  recentTrackIds: string[];
  recentArtistIds: string[];
};

export function isTasteEmpty(taste: MusicTaste | null | undefined): boolean {
  if (!taste) return true;
  return (
    taste.trackIds.length === 0 &&
    taste.artistIds.length === 0 &&
    taste.genres.length === 0 &&
    taste.recentTrackIds.length === 0 &&
    taste.recentArtistIds.length === 0
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

export type MusicCompatibility = {
  score: number;
  sharedTracks: string[];
  sharedArtists: string[];
  sharedGenres: string[];
};

export function scoreMusicCompatibility(
  viewer: MusicTaste,
  candidate: MusicTaste,
): MusicCompatibility {
  if (isTasteEmpty(viewer) || isTasteEmpty(candidate)) {
    return {score: 0, sharedTracks: [], sharedArtists: [], sharedGenres: []};
  }
  const sharedTracks = intersect(viewer.trackIds, candidate.trackIds);
  const sharedArtists = intersect(viewer.artistIds, candidate.artistIds);
  const sharedGenres = intersect(viewer.genres, candidate.genres);
  const recentTracks = intersect(viewer.recentTrackIds, candidate.recentTrackIds);
  const recentArtists = intersect(viewer.recentArtistIds, candidate.recentArtistIds);
  const viewerRecent = viewer.recentTrackIds.length + viewer.recentArtistIds.length;
  const candidateRecent = candidate.recentTrackIds.length + candidate.recentArtistIds.length;
  const denom = Math.min(viewerRecent, candidateRecent);
  const recent = denom <= 0
    ? 0
    : Math.min(1, (recentTracks.length + recentArtists.length) / denom);
  const weighted =
    overlap(viewer.trackIds, candidate.trackIds) * 0.4 +
    overlap(viewer.artistIds, candidate.artistIds) * 0.3 +
    overlap(viewer.genres, candidate.genres) * 0.2 +
    recent * 0.1;
  return {
    score: Math.max(0, Math.min(100, Math.round(weighted * 100))),
    sharedTracks,
    sharedArtists,
    sharedGenres,
  };
}

export function musicRankingBonus(score: number): number {
  if (score <= 0) return 0;
  return Math.max(0, Math.min(15, Math.round(score * MUSIC_RANKING_WEIGHT)));
}

export function interestedInAllows(interestedIn: unknown, gender: unknown): boolean {
  const want = typeof interestedIn === "string" ? interestedIn.trim().toLowerCase() : "";
  if (!want || want === "everyone") return true;
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
