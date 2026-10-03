import {
  curatedGiphyContentId,
  curatedKlipyContentId,
  giphyStableStillUrl,
  giphyStableWebpUrl,
  GIPHY_ID_PATTERN,
} from "./calibrationSeed.js";
import {isHumorCategory, type HumorCategory} from "./categories.js";
import {isAllowedMediaUrl} from "./contentValidation.js";
import {
  giphyAttribution,
  mapGiphyGif,
  pickGifImageRendition,
  pickPoster,
  type GiphyGif,
  type GiphyHumorSource,
} from "./giphySource.js";
import {
  KLIPY_CONTENT_FILTER,
  klipyIdOf,
  mapKlipyClip,
  pickKlipyPoster,
  pickKlipyVideo,
  type KlipyClip,
  type KlipyHumorSource,
} from "./klipySource.js";
import {assessProviderRelevance, providerSourceTrust} from "./providerRelevance.js";
import type {HumorSourceTrust} from "./types.js";

/**
 * Candidate harvesting for the curated GIPHY catalogue (dev tooling).
 *
 * Runs GIPHY searches and returns what a curator needs to judge each result —
 * its own title, credit, rating, renditions with sizes, still, and the
 * verdict the ordinary sync's relevance filter would give it. It writes
 * nothing anywhere: choosing an item is a human decision recorded in
 * `calibrationSeed.ts`, never a side effect of searching.
 *
 * Only reachable through the emulator-only `searchHumorProviderCandidates`
 * callable; errors carry the provider status only, never a URL (the request
 * URL holds the API key).
 */

export const MAX_CANDIDATE_QUERIES = 12;
export const MAX_CANDIDATES_PER_QUERY = 50;
export const DEFAULT_CANDIDATES_PER_QUERY = 25;
export const MAX_CANDIDATE_OFFSET = 4999;
export const CANDIDATE_RATINGS = ["g", "pg", "pg-13"] as const;

/** Where the curator searches. GIPHY is the default, as it always was. */
export const CANDIDATE_PROVIDERS = ["giphy", "klipy"] as const;
export type CandidateProvider = (typeof CANDIDATE_PROVIDERS)[number];

/** Reads `provider` from a callable payload; absent means GIPHY. */
export function parseCandidateProvider(
  raw: unknown,
): {ok: true; value: CandidateProvider} | {ok: false; field: "provider"} {
  const provider =
    raw && typeof raw === "object" && !Array.isArray(raw)
      ? (raw as Record<string, unknown>).provider
      : undefined;
  if (provider === undefined || provider === null) return {ok: true, value: "giphy"};
  return (CANDIDATE_PROVIDERS as readonly unknown[]).includes(provider)
    ? {ok: true, value: provider as CandidateProvider}
    : {ok: false, field: "provider"};
}

export type ProviderCandidateSearchInput = {
  queries: string[];
  perQuery: number;
  lang: "tr" | "en";
  offset: number;
  rating: (typeof CANDIDATE_RATINGS)[number];
  /** The humour dimension the queries probe, if the caller knows it. */
  dimension: HumorCategory | null;
};

export type ParseResult =
  | {ok: true; value: ProviderCandidateSearchInput}
  | {ok: false; field: string};

function boundedInt(raw: unknown, min: number, max: number, fallback: number): number | null {
  if (raw === undefined || raw === null) return fallback;
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw < min || raw > max) return null;
  return raw;
}

export function parseProviderCandidateSearchInput(raw: unknown): ParseResult {
  const data = (raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {}) as Record<
    string,
    unknown
  >;
  if (!Array.isArray(data.queries) || data.queries.length === 0) {
    return {ok: false, field: "queries"};
  }
  if (data.queries.length > MAX_CANDIDATE_QUERIES) {
    return {ok: false, field: "queries"};
  }
  const queries: string[] = [];
  for (const q of data.queries) {
    if (typeof q !== "string") return {ok: false, field: "queries"};
    const query = q.replace(/\s+/g, " ").trim();
    if (!query || query.length > 50) return {ok: false, field: "queries"};
    if (!queries.includes(query)) queries.push(query);
  }
  const perQuery = boundedInt(data.perQuery, 1, MAX_CANDIDATES_PER_QUERY, DEFAULT_CANDIDATES_PER_QUERY);
  if (perQuery === null) return {ok: false, field: "perQuery"};
  const offset = boundedInt(data.offset, 0, MAX_CANDIDATE_OFFSET, 0);
  if (offset === null) return {ok: false, field: "offset"};
  const lang = data.lang ?? "tr";
  if (lang !== "tr" && lang !== "en") return {ok: false, field: "lang"};
  const rating = data.rating ?? "pg-13";
  if (!(CANDIDATE_RATINGS as readonly unknown[]).includes(rating)) {
    return {ok: false, field: "rating"};
  }
  let dimension: HumorCategory | null = null;
  if (data.dimension !== undefined && data.dimension !== null) {
    if (typeof data.dimension !== "string" || !isHumorCategory(data.dimension)) {
      return {ok: false, field: "dimension"};
    }
    dimension = data.dimension;
  }
  return {
    ok: true,
    value: {
      queries,
      perQuery,
      lang,
      offset,
      rating: rating as ProviderCandidateSearchInput["rating"],
      dimension,
    },
  };
}

type Numeric = string | number | null | undefined;

function num(value: Numeric): number | null {
  if (value === undefined || value === null || value === "") return null;
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? n : null;
}

function str(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value : null;
}

export type CandidateRendition = {
  name: string;
  url: string;
  sizeBytes: number | null;
  width: number | null;
  height: number | null;
  mimeHint: string;
};

export type ProviderCandidate = {
  giphyId: string;
  /** The id this item would get in the curated catalogue. */
  proposedContentId: string;
  /** Every query in this search that returned it, in order. */
  queries: string[];
  /** Position in the first query that returned it (offset included). */
  rank: number;
  /** GIPHY's title, cleaned exactly as the catalogue would store it; or null. */
  title: string | null;
  rawTitle: string | null;
  slug: string | null;
  altText: string | null;
  username: string | null;
  displayName: string | null;
  verified: boolean;
  /** The item's GIPHY page. */
  sourceUrl: string | null;
  rating: string | null;
  isSticker: boolean;
  /** Tier the ordinary sync would give it (a curated entry becomes "curated"). */
  providerTrust: HumorSourceTrust;
  media: {
    /** What the catalogue would serve: see pickGifImageRendition. */
    rendition: CandidateRendition | null;
    /** `images.original.webp`, whatever its size. */
    originalWebp: CandidateRendition | null;
    stableWebpUrl: string;
    /** A real still of this item (fixed_height_still, else original_still). */
    stillUrl: string | null;
    stableStillUrl: string;
    width: number | null;
    height: number | null;
    aspectRatio: number | null;
  };
  /** The ordinary sync's relevance verdict. Advisory only for curation. */
  relevance: {ok: boolean; basis: string | null; reason: string | null};
};

export type ProviderQueryReport = {
  query: string;
  received: number;
  total: number | null;
  /** Provider failure (status only), or null. */
  error: string | null;
};

export type ProviderCandidateSearchResult = {
  lang: "tr" | "en";
  perQuery: number;
  offset: number;
  rating: string;
  dimension: HumorCategory | null;
  queries: ProviderQueryReport[];
  candidates: ProviderCandidate[];
  counts: {received: number; unique: number; relevant: number};
};

export function candidateFromGif(
  gif: GiphyGif,
  ctx: {query: string; rank: number; lang: "tr" | "en"; dimension: HumorCategory | null},
): ProviderCandidate | null {
  const giphyId = str(gif?.id);
  if (!giphyId || !GIPHY_ID_PATTERN.test(giphyId)) {
    return null;
  }
  const attribution = giphyAttribution(gif);
  const outcome = mapGiphyGif(gif, {
    language: ctx.lang,
    family: {query: ctx.query, language: ctx.lang, category: ctx.dimension ?? "meme"},
  });
  let relevance: ProviderCandidate["relevance"];
  let title: string | null = null;
  let isSticker = gif.is_sticker === 1 || gif.is_sticker === true || gif.type === "sticker";
  if (outcome.ok) {
    // Without a known dimension the query context must not vouch for an
    // unverified item's humour, exactly as an untagged sync would not.
    const item = ctx.dimension ? outcome.item : {...outcome.item, queryCategory: null};
    title = item.title ?? null;
    isSticker = item.isSticker === true;
    const verdict = assessProviderRelevance(item);
    relevance = verdict.ok
      ? {ok: true, basis: verdict.basis, reason: null}
      : {ok: false, basis: null, reason: verdict.reason};
  } else {
    relevance = {ok: false, basis: null, reason: outcome.reason};
  }

  const images = gif.images ?? {};
  const picked = pickGifImageRendition(images);
  const original = images.original;
  const originalWebp =
    original && isAllowedMediaUrl(original.webp)
      ? {
          name: "original.webp",
          url: original.webp!,
          sizeBytes: num(original.webp_size),
          width: num(original.width),
          height: num(original.height),
          mimeHint: "image/webp",
        }
      : null;
  const width = num(original?.width) ?? picked?.width ?? null;
  const height = num(original?.height) ?? picked?.height ?? null;

  return {
    giphyId,
    proposedContentId: curatedGiphyContentId(giphyId),
    queries: [ctx.query],
    rank: ctx.rank,
    title,
    rawTitle: str(gif.title),
    slug: str(gif.slug),
    altText: str(gif.alt_text),
    username: attribution.username,
    displayName: attribution.displayName,
    verified: attribution.verified,
    sourceUrl: attribution.sourceUrl,
    rating: str(gif.rating),
    isSticker,
    providerTrust: providerSourceTrust(attribution),
    media: {
      rendition: picked
        ? {
            name: picked.name,
            url: picked.url,
            sizeBytes: picked.sizeBytes,
            width: picked.width,
            height: picked.height,
            mimeHint: picked.mimeHint,
          }
        : null,
      originalWebp,
      stableWebpUrl: giphyStableWebpUrl(giphyId),
      stillUrl: pickPoster(images),
      stableStillUrl: giphyStableStillUrl(giphyId),
      width,
      height,
      aspectRatio: width && height ? Math.round((width / height) * 1000) / 1000 : null,
    },
    relevance,
  };
}

type CandidateSource = Pick<GiphyHumorSource, "searchGifsRaw">;

/**
 * Runs every query and merges the results by GIPHY id, keeping first-seen
 * order. Read-only: the only side effect is the provider requests.
 */
export async function searchProviderCandidates(
  source: CandidateSource,
  input: ProviderCandidateSearchInput,
): Promise<ProviderCandidateSearchResult> {
  const byId = new Map<string, ProviderCandidate>();
  const reports: ProviderQueryReport[] = [];
  let received = 0;

  for (const query of input.queries) {
    try {
      const page = await source.searchGifsRaw({
        query,
        language: input.lang,
        limit: input.perQuery,
        offset: input.offset,
      });
      received += page.gifs.length;
      reports.push({query, received: page.gifs.length, total: page.total, error: null});
      page.gifs.forEach((gif, index) => {
        const candidate = candidateFromGif(gif, {
          query,
          rank: input.offset + index,
          lang: input.lang,
          dimension: input.dimension,
        });
        if (!candidate) return;
        const existing = byId.get(candidate.giphyId);
        if (existing) {
          if (!existing.queries.includes(query)) existing.queries.push(query);
        } else {
          byId.set(candidate.giphyId, candidate);
        }
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : "giphy-error";
      reports.push({
        query,
        received: 0,
        total: null,
        // Status-shaped messages only; anything else is reduced to a code.
        error: /^giphy-[a-z0-9-]+$/.test(message) ? message : "giphy-error",
      });
    }
  }

  const candidates = [...byId.values()];
  return {
    lang: input.lang,
    perQuery: input.perQuery,
    offset: input.offset,
    rating: input.rating,
    dimension: input.dimension,
    queries: reports,
    candidates,
    counts: {
      received,
      unique: candidates.length,
      relevant: candidates.filter((c) => c.relevance.ok).length,
    },
  };
}

// --------------------------------------------------------------------------
// KLIPY clips (short videos)
// --------------------------------------------------------------------------

/**
 * One KLIPY clip as a curator needs it: its own title, its page, the MP4 that
 * would be served and the preview that would be its poster. KLIPY names no
 * uploader and sends no duration, so neither appears here; the review page
 * measures the duration from the file when a clip is picked.
 */
export type KlipyClipCandidate = {
  provider: "klipy";
  klipyId: string;
  /** The id this clip would get in the curated catalogue. */
  proposedContentId: string;
  /** Every query in this search that returned it, in order. */
  queries: string[];
  /** Position in the first query that returned it (offset included). */
  rank: number;
  /** KLIPY's title, cleaned exactly as the catalogue would store it; or null. */
  title: string | null;
  rawTitle: string | null;
  /** The clip's klipy.com page. */
  sourceUrl: string | null;
  media: {
    mp4: CandidateRendition;
    /** The clip's own animated preview (WebP, else GIF), or null. */
    poster: CandidateRendition | null;
    width: number | null;
    height: number | null;
    aspectRatio: number | null;
  };
};

export type KlipyCandidateSearchResult = {
  provider: "klipy";
  lang: "tr" | "en";
  perQuery: number;
  offset: number;
  /** The content filter every request was sent with. */
  contentFilter: string;
  dimension: HumorCategory | null;
  queries: ProviderQueryReport[];
  candidates: KlipyClipCandidate[];
  /** Results the adapter would not serve (ads, oversized, no MP4), by reason. */
  rejected: Record<string, number>;
  counts: {received: number; unique: number};
};

export function candidateFromKlipyClip(
  clip: KlipyClip,
  ctx: {query: string; rank: number; lang: "tr" | "en"},
): {ok: true; candidate: KlipyClipCandidate} | {ok: false; reason: string} {
  const outcome = mapKlipyClip(clip, {language: ctx.lang, query: ctx.query});
  if (!outcome.ok) {
    return {ok: false, reason: outcome.reason};
  }
  const klipyId = klipyIdOf(clip);
  const video = pickKlipyVideo(clip);
  if (!klipyId || !video.ok) {
    return {ok: false, reason: "missing-media"};
  }
  const poster = pickKlipyPoster(clip);
  const {item} = outcome;
  return {
    ok: true,
    candidate: {
      provider: "klipy",
      klipyId,
      proposedContentId: curatedKlipyContentId(klipyId),
      queries: [ctx.query],
      rank: ctx.rank,
      title: item.title ?? null,
      rawTitle: item.rawTitle ?? null,
      sourceUrl: item.sourceUrl ?? null,
      media: {
        mp4: {...video.rendition},
        poster: poster ? {...poster} : null,
        width: video.rendition.width,
        height: video.rendition.height,
        aspectRatio: item.media.aspectRatio ?? null,
      },
    },
  };
}

type KlipyCandidateSource = Pick<KlipyHumorSource, "searchClipsRaw">;

/**
 * Runs every query against KLIPY clips and merges the results by clip id,
 * keeping first-seen order. Read-only: the only side effect is one provider
 * request per query. `rating` does not apply — KLIPY has one content filter,
 * and every request uses its strictest level.
 */
export async function searchKlipyClipCandidates(
  source: KlipyCandidateSource,
  input: ProviderCandidateSearchInput,
): Promise<KlipyCandidateSearchResult> {
  const byId = new Map<string, KlipyClipCandidate>();
  const reports: ProviderQueryReport[] = [];
  const rejected: Record<string, number> = {};
  let received = 0;
  // KLIPY pages by number; an offset is the page that starts at it.
  const page = Math.floor(input.offset / input.perQuery) + 1;
  const firstRank = (page - 1) * input.perQuery;

  for (const query of input.queries) {
    try {
      const result = await source.searchClipsRaw({
        query,
        language: input.lang,
        limit: input.perQuery,
        page,
      });
      received += result.clips.length;
      reports.push({query, received: result.clips.length, total: null, error: null});
      result.clips.forEach((clip, index) => {
        const mapped = candidateFromKlipyClip(clip, {
          query,
          rank: firstRank + index,
          lang: input.lang,
        });
        if (!mapped.ok) {
          rejected[mapped.reason] = (rejected[mapped.reason] ?? 0) + 1;
          return;
        }
        const existing = byId.get(mapped.candidate.klipyId);
        if (existing) {
          if (!existing.queries.includes(query)) existing.queries.push(query);
        } else {
          byId.set(mapped.candidate.klipyId, mapped.candidate);
        }
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : "klipy-error";
      reports.push({
        query,
        received: 0,
        total: null,
        // Status-shaped messages only; anything else is reduced to a code.
        error: /^klipy-[a-z0-9-]+$/.test(message) ? message : "klipy-error",
      });
    }
  }

  const candidates = [...byId.values()];
  return {
    provider: "klipy",
    lang: input.lang,
    perQuery: input.perQuery,
    offset: input.offset,
    contentFilter: KLIPY_CONTENT_FILTER,
    dimension: input.dimension,
    queries: reports,
    candidates,
    rejected,
    counts: {received, unique: candidates.length},
  };
}
