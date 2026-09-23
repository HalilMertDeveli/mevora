/**
 * Public Spotify music profile.
 *
 * Mevora keeps two Spotify datasets that must not blur into each other:
 *
 *  - `users/{uid}/music/summary` — the imported taste. Rich, private, and used
 *    only for compatibility. It holds recently-played tracks, playlist track
 *    ids and a fingerprint, none of which another member may ever read.
 *  - `profiles/{uid}.publicMusic` — what the member deliberately chose to show
 *    on their dating profile. At most three artists, three tracks and a short
 *    genre line, built here from the private summary.
 *
 * Everything in the public shape is resolved server-side from the summary. The
 * client sends identifiers only, so a caller cannot invent an artist name, an
 * artwork URL or a Spotify link, and cannot publish an artist they never
 * listened to.
 */

export const MAX_PUBLIC_ARTISTS = 3;
export const MAX_PUBLIC_TRACKS = 3;
export const MAX_PUBLIC_GENRES = 3;

/** Spotify open.spotify.com links, built from ids we already trust. */
const SPOTIFY_ARTIST_URL = "https://open.spotify.com/artist/";
const SPOTIFY_TRACK_URL = "https://open.spotify.com/track/";

export type PublicMusicArtist = {
  id: string;
  name: string;
  imageUrl: string | null;
  spotifyUrl: string;
};

export type PublicMusicTrack = {
  id: string;
  name: string;
  artist: string;
  imageUrl: string | null;
  spotifyUrl: string;
};

export type PublicMusicProfile = {
  enabled: boolean;
  artists: PublicMusicArtist[];
  tracks: PublicMusicTrack[];
  genres: string[];
};

/** What a member with no public music looks like. Never `undefined`. */
export function emptyPublicMusicProfile(): PublicMusicProfile {
  return {enabled: false, artists: [], tracks: [], genres: []};
}

export class PublicMusicValidationError extends Error {
  constructor(readonly reason: string) {
    super(reason);
    this.name = "PublicMusicValidationError";
  }
}

/**
 * Normalizes a client-supplied id list.
 *
 * Duplicates collapse rather than reject: selecting the same artist twice is a
 * UI slip, not an attack, and collapsing keeps the limit meaningful. The limit
 * is checked after collapsing so `[a, a, b, c]` is three distinct artists, not
 * a rejected four.
 */
export function normalizeSelectionIds(
  value: unknown,
  limit: number,
  field: string,
): string[] {
  if (value === undefined || value === null) {
    return [];
  }
  if (!Array.isArray(value)) {
    throw new PublicMusicValidationError(`${field}-invalid`);
  }
  const seen = new Set<string>();
  for (const entry of value) {
    if (typeof entry !== "string") {
      throw new PublicMusicValidationError(`${field}-invalid`);
    }
    const id = entry.trim();
    if (id.length === 0) {
      throw new PublicMusicValidationError(`${field}-invalid`);
    }
    seen.add(id);
  }
  if (seen.size > limit) {
    throw new PublicMusicValidationError(`${field}-limit`);
  }
  return [...seen];
}

type CatalogEntry = {
  id: string;
  name: string;
  artist?: string;
  image?: string | null;
  genres?: string[];
};

function readCatalog(raw: unknown): Map<string, CatalogEntry> {
  const out = new Map<string, CatalogEntry>();
  if (!Array.isArray(raw)) {
    return out;
  }
  for (const item of raw) {
    if (!item || typeof item !== "object") {
      continue;
    }
    const record = item as Record<string, unknown>;
    const id = typeof record.id === "string" ? record.id.trim() : "";
    if (!id || out.has(id)) {
      continue;
    }
    out.set(id, {
      id,
      name: typeof record.name === "string" ? record.name : "",
      artist: typeof record.artist === "string" ? record.artist : undefined,
      image: typeof record.image === "string" && record.image.length > 0
        ? record.image
        : null,
      genres: Array.isArray(record.genres)
        ? record.genres.filter((g): g is string => typeof g === "string")
        : undefined,
    });
  }
  return out;
}

/**
 * The artists a member may publish: their imported top artists.
 *
 * Recently-played artists are deliberately excluded. They are private listening
 * activity, and publishing from them would let the profile leak what somebody
 * happened to play this week.
 */
export function selectableArtists(summary: unknown): Map<string, CatalogEntry> {
  const data = (summary ?? {}) as Record<string, unknown>;
  return readCatalog(data.topArtists);
}

/** The tracks a member may publish: imported top tracks only. */
export function selectableTracks(summary: unknown): Map<string, CatalogEntry> {
  const data = (summary ?? {}) as Record<string, unknown>;
  return readCatalog(data.topTracks);
}

/**
 * Derives the short public genre line.
 *
 * Taken from the genres of the artists the member actually published, so the
 * line always describes what is on the card. Falls back to the summary's
 * ranked genre shares when the selected artists carry no genre data.
 */
export function derivePublicGenres(
  artists: PublicMusicArtist[],
  catalog: Map<string, CatalogEntry>,
  summary: unknown,
): string[] {
  const counts = new Map<string, number>();
  for (const artist of artists) {
    for (const genre of catalog.get(artist.id)?.genres ?? []) {
      const key = genre.trim().toLowerCase();
      if (key.length === 0) {
        continue;
      }
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }
  }
  if (counts.size > 0) {
    return [...counts.entries()]
      .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
      .slice(0, MAX_PUBLIC_GENRES)
      .map(([name]) => name);
  }
  const data = (summary ?? {}) as Record<string, unknown>;
  const profile = (data.musicProfile ?? {}) as Record<string, unknown>;
  const shares = Array.isArray(profile.genres) ? profile.genres : [];
  const names: string[] = [];
  for (const share of shares) {
    if (!share || typeof share !== "object") {
      continue;
    }
    const name = (share as {name?: unknown}).name;
    if (typeof name === "string" && name.trim().length > 0) {
      names.push(name.trim().toLowerCase());
    }
    if (names.length >= MAX_PUBLIC_GENRES) {
      break;
    }
  }
  return names;
}

/**
 * Builds the public profile from ids the caller selected.
 *
 * Every field on the result comes from `summary` — the caller's own imported
 * Spotify data. An id that is not in that data is rejected rather than
 * silently dropped, so a client cannot discover which ids exist by probing,
 * and cannot publish somebody else's artist.
 */
export function buildPublicMusicProfile(input: {
  enabled: boolean;
  artistIds: string[];
  trackIds: string[];
  summary: unknown;
}): PublicMusicProfile {
  const artistCatalog = selectableArtists(input.summary);
  const trackCatalog = selectableTracks(input.summary);

  const artists: PublicMusicArtist[] = [];
  for (const id of input.artistIds) {
    const entry = artistCatalog.get(id);
    if (!entry) {
      throw new PublicMusicValidationError("artist-not-in-library");
    }
    artists.push({
      id: entry.id,
      name: entry.name,
      imageUrl: entry.image ?? null,
      spotifyUrl: `${SPOTIFY_ARTIST_URL}${entry.id}`,
    });
  }

  const tracks: PublicMusicTrack[] = [];
  for (const id of input.trackIds) {
    const entry = trackCatalog.get(id);
    if (!entry) {
      throw new PublicMusicValidationError("track-not-in-library");
    }
    tracks.push({
      id: entry.id,
      name: entry.name,
      artist: entry.artist ?? "",
      imageUrl: entry.image ?? null,
      spotifyUrl: `${SPOTIFY_TRACK_URL}${entry.id}`,
    });
  }

  // Nothing selected means nothing to show, whatever the flag says — an empty
  // card on a dating profile is worse than no card.
  const hasSelection = artists.length > 0 || tracks.length > 0;
  const enabled = input.enabled && hasSelection;

  return {
    enabled,
    artists,
    tracks,
    genres: enabled
      ? derivePublicGenres(artists, artistCatalog, input.summary)
      : [],
  };
}

/**
 * Re-resolves an existing public profile against a freshly synced summary.
 *
 * A published choice is the member's, not Spotify's: a re-sync must never swap
 * their three artists for this month's top three. Selections are therefore kept
 * as long as they are still present in the imported data, and their names and
 * artwork are refreshed from it. Anything Spotify no longer returns is dropped,
 * because there is no trustworthy source for its metadata any more.
 */
export function reconcilePublicMusicProfile(
  existing: unknown,
  summary: unknown,
): PublicMusicProfile {
  const current = (existing ?? {}) as Record<string, unknown>;
  const artistIds = Array.isArray(current.artists)
    ? current.artists
      .map((a) => (a && typeof a === "object" ? (a as {id?: unknown}).id : null))
      .filter((id): id is string => typeof id === "string")
    : [];
  const trackIds = Array.isArray(current.tracks)
    ? current.tracks
      .map((t) => (t && typeof t === "object" ? (t as {id?: unknown}).id : null))
      .filter((id): id is string => typeof id === "string")
    : [];

  const artistCatalog = selectableArtists(summary);
  const trackCatalog = selectableTracks(summary);
  const survivingArtists = artistIds.filter((id) => artistCatalog.has(id));
  const survivingTracks = trackIds.filter((id) => trackCatalog.has(id));

  return buildPublicMusicProfile({
    enabled: current.enabled === true,
    artistIds: survivingArtists,
    trackIds: survivingTracks,
    summary,
  });
}

/**
 * The profile-card shape other members receive.
 *
 * This is the only Spotify data that leaves the owner's own documents, so it is
 * built field by field rather than by spreading anything.
 */
export function toPublicMusicCard(
  raw: unknown,
): Record<string, unknown> | null {
  const data = (raw ?? {}) as Record<string, unknown>;
  if (data.enabled !== true) {
    return null;
  }
  const artists = Array.isArray(data.artists) ? data.artists : [];
  const tracks = Array.isArray(data.tracks) ? data.tracks : [];
  if (artists.length === 0 && tracks.length === 0) {
    return null;
  }
  return {
    enabled: true,
    artists: artists.slice(0, MAX_PUBLIC_ARTISTS).map((artist) => {
      const item = (artist ?? {}) as Record<string, unknown>;
      return {
        id: typeof item.id === "string" ? item.id : "",
        name: typeof item.name === "string" ? item.name : "",
        imageUrl: typeof item.imageUrl === "string" ? item.imageUrl : null,
        spotifyUrl: typeof item.spotifyUrl === "string" ? item.spotifyUrl : "",
      };
    }),
    tracks: tracks.slice(0, MAX_PUBLIC_TRACKS).map((track) => {
      const item = (track ?? {}) as Record<string, unknown>;
      return {
        id: typeof item.id === "string" ? item.id : "",
        name: typeof item.name === "string" ? item.name : "",
        artist: typeof item.artist === "string" ? item.artist : "",
        imageUrl: typeof item.imageUrl === "string" ? item.imageUrl : null,
        spotifyUrl: typeof item.spotifyUrl === "string" ? item.spotifyUrl : "",
      };
    }),
    genres: (Array.isArray(data.genres) ? data.genres : [])
      .filter((genre): genre is string => typeof genre === "string")
      .slice(0, MAX_PUBLIC_GENRES),
  };
}
