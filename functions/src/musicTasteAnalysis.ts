/**
 * The member's general music taste, derived from what they listen to over
 * months rather than what they happened to play this week.
 *
 * Spotify's `/me/top/{type}` computes affinity over three windows. This module
 * reads the two broad ones — `medium_term` (about six months) and `long_term`
 * (the account's lifetime) — and asks a narrow question of them: what keeps
 * coming back? An artist present in both windows is part of who this person
 * is; one that appears only in the last few weeks is a mood. Short-term and
 * recently-played data stay out of this entirely, and out of the profile.
 *
 * Everything here is a pure function of the two lists. No inference about the
 * listener, no personality claims — only counts, overlaps and orderings that
 * can be checked against the input.
 */

export type TasteArtist = {
  id: string;
  name: string;
  genres?: string[];
};

export type TasteTrack = {
  id: string;
  name: string;
};

/** Ordered genres, most characteristic first. */
export const MAX_TASTE_GENRES = 5;

/** The artists the summary names. */
export const MAX_SIGNATURE_ARTISTS = 3;

/**
 * An artist that appears in both windows counts for more than one that appears
 * in a single window, and the longer window counts for slightly more than the
 * medium one. The weights are deliberately small integers: the ordering they
 * produce should be explainable from the input, not tuned.
 */
const WEIGHT_LONG = 3;
const WEIGHT_MEDIUM = 2;

export type GeneralMusicTaste = {
  /** The genre that best characterises the member, or null with no data. */
  dominantGenre: string | null;
  /** Genres after the dominant one, in order. */
  secondaryGenres: string[];
  /** Dominant plus secondary, capped — what a profile shows. */
  genres: string[];
  /** Artists the member returns to, most characteristic first. */
  signatureArtists: Array<{id: string; name: string}>;
  /** Artists present in both windows. A measure of a settled taste. */
  stableArtistCount: number;
  /** Tracks present in both windows. */
  stableTrackCount: number;
  /** Distinct artists across both windows. A measure of breadth. */
  artistBreadth: number;
};

export function emptyGeneralMusicTaste(): GeneralMusicTaste {
  return {
    dominantGenre: null,
    secondaryGenres: [],
    genres: [],
    signatureArtists: [],
    stableArtistCount: 0,
    stableTrackCount: 0,
    artistBreadth: 0,
  };
}

function cleanGenre(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim().toLowerCase();
  return trimmed.length > 0 ? trimmed : null;
}

function idsOf(items: ReadonlyArray<{id?: unknown}>): Set<string> {
  const out = new Set<string>();
  for (const item of items) {
    if (typeof item?.id === "string" && item.id.length > 0) {
      out.add(item.id);
    }
  }
  return out;
}

/**
 * Builds the general taste summary from the two broad Spotify windows.
 *
 * Ties break on first appearance in the long-term list and then the medium-term
 * one, so the same input always produces the same summary — a profile that
 * reshuffles itself between syncs would read as noise.
 */
export function deriveGeneralMusicTaste(input: {
  longTermArtists?: ReadonlyArray<TasteArtist>;
  mediumTermArtists?: ReadonlyArray<TasteArtist>;
  longTermTracks?: ReadonlyArray<TasteTrack>;
  mediumTermTracks?: ReadonlyArray<TasteTrack>;
}): GeneralMusicTaste {
  const longArtists = input.longTermArtists ?? [];
  const mediumArtists = input.mediumTermArtists ?? [];
  const longTracks = input.longTermTracks ?? [];
  const mediumTracks = input.mediumTermTracks ?? [];

  if (longArtists.length === 0 && mediumArtists.length === 0) {
    return emptyGeneralMusicTaste();
  }

  const longIds = idsOf(longArtists);
  const mediumIds = idsOf(mediumArtists);

  // Rank order matters: an artist at the top of a window says more than one at
  // the bottom, so position contributes a small, bounded bonus.
  const score = new Map<string, number>();
  const nameById = new Map<string, string>();
  const firstSeen = new Map<string, number>();
  let order = 0;

  const absorb = (
    artists: ReadonlyArray<TasteArtist>,
    weight: number,
  ): void => {
    artists.forEach((artist, index) => {
      if (typeof artist?.id !== "string" || artist.id.length === 0) {
        return;
      }
      const positional = Math.max(0, artists.length - index) / artists.length;
      score.set(artist.id, (score.get(artist.id) ?? 0) + weight + positional);
      if (!nameById.has(artist.id)) {
        nameById.set(artist.id, typeof artist.name === "string" ? artist.name : "");
        firstSeen.set(artist.id, order++);
      }
    });
  };

  absorb(longArtists, WEIGHT_LONG);
  absorb(mediumArtists, WEIGHT_MEDIUM);

  const ranked = [...score.entries()].sort((a, b) => {
    if (b[1] !== a[1]) {
      return b[1] - a[1];
    }
    return (firstSeen.get(a[0]) ?? 0) - (firstSeen.get(b[0]) ?? 0);
  });

  const signatureArtists = ranked
    .slice(0, MAX_SIGNATURE_ARTISTS)
    .map(([id]) => ({id, name: nameById.get(id) ?? ""}))
    .filter((artist) => artist.name.length > 0);

  // Genres are weighted the same way, so a genre carried by a long-standing
  // favourite outranks one carried by a single recent addition.
  const genreScore = new Map<string, number>();
  const genreFirstSeen = new Map<string, number>();
  let genreOrder = 0;
  const absorbGenres = (
    artists: ReadonlyArray<TasteArtist>,
    weight: number,
  ): void => {
    for (const artist of artists) {
      for (const raw of artist?.genres ?? []) {
        const genre = cleanGenre(raw);
        if (genre === null) {
          continue;
        }
        genreScore.set(genre, (genreScore.get(genre) ?? 0) + weight);
        if (!genreFirstSeen.has(genre)) {
          genreFirstSeen.set(genre, genreOrder++);
        }
      }
    }
  };
  absorbGenres(longArtists, WEIGHT_LONG);
  absorbGenres(mediumArtists, WEIGHT_MEDIUM);

  const genres = [...genreScore.entries()]
    .sort((a, b) => {
      if (b[1] !== a[1]) {
        return b[1] - a[1];
      }
      return (genreFirstSeen.get(a[0]) ?? 0) - (genreFirstSeen.get(b[0]) ?? 0);
    })
    .slice(0, MAX_TASTE_GENRES)
    .map(([genre]) => genre);

  const stableArtistCount = [...longIds].filter((id) =>
    mediumIds.has(id),
  ).length;
  const longTrackIds = idsOf(longTracks);
  const mediumTrackIds = idsOf(mediumTracks);
  const stableTrackCount = [...longTrackIds].filter((id) =>
    mediumTrackIds.has(id),
  ).length;

  return {
    dominantGenre: genres[0] ?? null,
    secondaryGenres: genres.slice(1),
    genres,
    signatureArtists,
    stableArtistCount,
    stableTrackCount,
    artistBreadth: new Set([...longIds, ...mediumIds]).size,
  };
}

/**
 * The profile-safe projection.
 *
 * Only names and counts leave the backend — no ids a viewer could use to probe
 * the member's library, no timestamps, nothing from recently played.
 *
 * An artist is named only when the member chose to show that artist on their
 * card (`shownArtistIds`). The signature list is ranked from the whole private
 * library, and publishing it as it stands would name artists the member left
 * out of their selection. Genres and counts stay: they describe the taste
 * without naming anything the member did not pick.
 */
export type PublicGeneralTaste = {
  dominantGenre: string | null;
  secondaryGenres: string[];
  signatureArtists: string[];
  stableArtistCount: number;
  artistBreadth: number;
};

export function toPublicGeneralTaste(
  taste: GeneralMusicTaste,
  shownArtistIds: ReadonlySet<string>,
): PublicGeneralTaste {
  return {
    dominantGenre: taste.dominantGenre,
    secondaryGenres: taste.secondaryGenres.slice(0, 2),
    signatureArtists: taste.signatureArtists
      .filter((artist) => shownArtistIds.has(artist.id))
      .map((artist) => artist.name),
    stableArtistCount: taste.stableArtistCount,
    artistBreadth: taste.artistBreadth,
  };
}

/**
 * Reads a summary back in its *published* shape.
 *
 * The public projection flattens `signatureArtists` to names, so the private
 * reader — which expects `{id, name}` — silently drops every one of them. They
 * are different shapes and need different readers.
 */
export function readPublicGeneralTaste(value: unknown): PublicGeneralTaste {
  const empty: PublicGeneralTaste = {
    dominantGenre: null,
    secondaryGenres: [],
    signatureArtists: [],
    stableArtistCount: 0,
    artistBreadth: 0,
  };
  if (value === null || typeof value !== "object") {
    return empty;
  }
  const record = value as Record<string, unknown>;
  const names = (raw: unknown): string[] =>
    Array.isArray(raw) ?
      raw.filter(
        (item): item is string => typeof item === "string" && item.length > 0,
      ) :
      [];
  const count = (raw: unknown): number =>
    typeof raw === "number" && Number.isFinite(raw) && raw >= 0 ?
      Math.floor(raw) :
      0;
  return {
    dominantGenre:
      typeof record.dominantGenre === "string" && record.dominantGenre.length > 0 ?
        record.dominantGenre :
        null,
    secondaryGenres: names(record.secondaryGenres).slice(0, 2),
    signatureArtists: names(record.signatureArtists).slice(
      0,
      MAX_SIGNATURE_ARTISTS,
    ),
    stableArtistCount: count(record.stableArtistCount),
    artistBreadth: count(record.artistBreadth),
  };
}

/** True when a published summary has anything worth rendering. */
export function publicGeneralTasteHasContent(
  taste: PublicGeneralTaste,
): boolean {
  return (
    (taste.dominantGenre !== null && taste.dominantGenre.length > 0) ||
    taste.signatureArtists.length > 0
  );
}

/** Reads a stored summary back, tolerating anything malformed. */
export function readGeneralMusicTaste(value: unknown): GeneralMusicTaste {
  if (value === null || typeof value !== "object") {
    return emptyGeneralMusicTaste();
  }
  const record = value as Record<string, unknown>;
  const strings = (raw: unknown): string[] =>
    Array.isArray(raw) ?
      raw.filter((item): item is string => typeof item === "string") :
      [];
  const count = (raw: unknown): number =>
    typeof raw === "number" && Number.isFinite(raw) && raw >= 0 ?
      Math.floor(raw) :
      0;
  const genres = strings(record.genres).slice(0, MAX_TASTE_GENRES);
  return {
    dominantGenre:
      typeof record.dominantGenre === "string" ? record.dominantGenre : null,
    secondaryGenres: strings(record.secondaryGenres),
    genres,
    signatureArtists: Array.isArray(record.signatureArtists) ?
      record.signatureArtists
        .filter(
          (item): item is {id: string; name: string} =>
            item !== null &&
            typeof item === "object" &&
            typeof (item as {id?: unknown}).id === "string" &&
            typeof (item as {name?: unknown}).name === "string",
        )
        .slice(0, MAX_SIGNATURE_ARTISTS) :
      [],
    stableArtistCount: count(record.stableArtistCount),
    stableTrackCount: count(record.stableTrackCount),
    artistBreadth: count(record.artistBreadth),
  };
}
