/**
 * KLIPY Clips source (https://docs.klipy.com — Clips → Search).
 *
 * KLIPY "clips" are very short movie / TV moments with sound: one MP4 per
 * clip, plus an animated WebP and GIF preview of the same moment. This adapter
 * searches clips and maps each result to a `HumorSourceItem` of type "video".
 *
 * What the API sends, verified against a live search on 2026-10-03:
 *
 * - `GET {base}/{app_key}/clips/search?q&page&per_page&customer_id&locale&content_filter`.
 *   The key is part of the URL **path**, so a request URL is never logged,
 *   thrown or returned; errors carry the HTTP status only.
 * - `data.data[]`: `id` (a number that can exceed 2^53 — read as text, see
 *   {@link parseKlipyJson}), `url` (the clip's klipy.com page), `title`,
 *   `slug`, `file.{mp4,gif,webp}`, `file_meta.{mp4,gif,webp}.{width,height,size}`,
 *   `tags`, `type` ("clip"; "ad" when ads are enabled) and `blur_preview`.
 * - There is **no** duration, **no** uploader and **no** still image. The
 *   duration stays `null` here (never invented); the credit is the provider
 *   alone; the poster is the clip's own animated WebP (else GIF) preview.
 * - Media is served from `static.klipy.com` (see `KLIPY_MEDIA_HOSTS`), is not
 *   signed and carries no expiry parameter.
 *
 * Only the emulator-only curator search uses this source. It is not part of
 * `syncHumorFromProvider`, and nothing here writes anywhere.
 */
import {cleanProviderTitle} from "./giphySource.js";
import {isKlipyConfigured, resolveKlipyApiKey} from "./humorApiConfig.js";
import {KLIPY_MEDIA_HOSTS} from "./contentValidation.js";
import type {
  HumorContentSource,
  HumorSourceItem,
  HumorSourcePage,
} from "./sourceAdapter.js";
import type {HumorAttribution} from "./types.js";

export const KLIPY_API_BASE = "https://api.klipy.com/api/v1";

/** KLIPY ids as exact decimal strings. */
const KLIPY_ID = /^[0-9]{6,24}$/;

/**
 * The strictest content filter KLIPY offers, sent on every request. KLIPY's
 * levels are off / low / medium / high; its docs note the clips library is
 * not fully rated yet, so a person still watches every clip before it is used.
 */
export const KLIPY_CONTENT_FILTER = "high";

/**
 * KLIPY asks for a per-user id. Mevora sends this one fixed, non-personal
 * value — never a member uid, email or device id.
 */
export const KLIPY_CUSTOMER_ID = "mevora-curator";

/** `per_page` bounds of the clips search endpoint. */
export const KLIPY_MIN_PER_PAGE = 8;
export const KLIPY_MAX_PER_PAGE = 50;

/**
 * Largest MP4 served. Observed clips are 59–332 KB for 0.85–3.0 s (at most
 * about 135 KB per second), so 1.5 MB leaves room for a clip of roughly ten
 * seconds and still refuses anything that is not a short clip. GIPHY's MP4
 * cap, for comparison, is 2.5 MB.
 */
export const MAX_KLIPY_MP4_BYTES = 1_500_000;

/** Nothing above 720p: KLIPY sends one rendition, up to 1280 wide. */
export const MAX_KLIPY_VIDEO_WIDTH = 1280;
export const MAX_KLIPY_VIDEO_HEIGHT = 720;

/** Largest animated preview used as a poster (observed WebP: 16–175 KB). */
export const MAX_KLIPY_POSTER_BYTES = 600_000;

// --------------------------------------------------------------------------
// Raw provider shapes (only the fields we read)
// --------------------------------------------------------------------------

type Numeric = string | number | null | undefined;

export interface KlipyFileMeta {
  width?: Numeric;
  height?: Numeric;
  size?: Numeric;
}

export interface KlipyClip {
  /** A string after {@link parseKlipyJson}; a number only from a hand-built object. */
  id?: string | number;
  url?: string;
  title?: string;
  slug?: string;
  file?: {mp4?: string; gif?: string; webp?: string};
  file_meta?: {mp4?: KlipyFileMeta; gif?: KlipyFileMeta; webp?: KlipyFileMeta};
  tags?: unknown;
  type?: string;
}

function num(value: Numeric): number | null {
  if (value === undefined || value === null || value === "") return null;
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? n : null;
}

/**
 * Parses a KLIPY response body, keeping every `id` exact.
 *
 * KLIPY ids are 16-digit numbers and some are larger than 2^53, where
 * `JSON.parse` silently rounds — two different clips would get one id. Each
 * numeric `"id"` is therefore quoted before parsing. A `"id":` inside a string
 * value is written `\"id\":` in JSON and is not touched.
 */
export function parseKlipyJson(text: string): unknown {
  return JSON.parse(text.replace(/"id"\s*:\s*(\d+)/g, '"id":"$1"'));
}

/** The clip's id as an exact decimal string, or null. */
export function klipyIdOf(clip: KlipyClip | null | undefined): string | null {
  const raw = clip?.id;
  if (typeof raw === "string") {
    return KLIPY_ID.test(raw) ? raw : null;
  }
  if (typeof raw === "number" && Number.isSafeInteger(raw)) {
    const id = String(raw);
    return KLIPY_ID.test(id) ? id : null;
  }
  // A number past 2^53 has already lost digits: not this clip's id any more.
  return null;
}

/** An https URL on one of KLIPY's media hosts, as sent; else null. */
export function klipyMediaUrl(raw: unknown): string | null {
  if (typeof raw !== "string" || !raw.trim()) return null;
  let parsed: URL;
  try {
    parsed = new URL(raw.trim());
  } catch {
    return null;
  }
  if (parsed.protocol !== "https:") return null;
  const host = parsed.hostname.toLowerCase();
  return KLIPY_MEDIA_HOSTS.includes(host) ? raw.trim() : null;
}

/** The clip's klipy.com page (https) as sent, else null. */
export function klipyPageUrl(raw: unknown): string | null {
  if (typeof raw !== "string" || !raw.trim()) return null;
  try {
    const parsed = new URL(raw.trim());
    const host = parsed.hostname.toLowerCase();
    if (parsed.protocol !== "https:") return null;
    return host === "klipy.com" || host === "www.klipy.com" ? raw.trim() : null;
  } catch {
    return null;
  }
}

export type KlipyRendition = {
  name: "mp4" | "webp" | "gif";
  url: string;
  sizeBytes: number | null;
  width: number | null;
  height: number | null;
  mimeHint: string;
};

function rendition(
  clip: KlipyClip,
  name: KlipyRendition["name"],
  mimeHint: string,
): KlipyRendition | null {
  const url = klipyMediaUrl(clip.file?.[name]);
  if (!url) return null;
  const meta = clip.file_meta?.[name];
  return {
    name,
    url,
    sizeBytes: num(meta?.size),
    width: num(meta?.width),
    height: num(meta?.height),
    mimeHint,
  };
}

export type KlipyVideoChoice =
  | {ok: true; rendition: KlipyRendition}
  | {ok: false; reason: string};

/**
 * The clip's MP4, if it may be served.
 *
 * KLIPY sends exactly one MP4 per clip, so there is nothing to choose
 * between — only whether to accept it: https on a KLIPY media host, a `.mp4`
 * file, a known size of at most {@link MAX_KLIPY_MP4_BYTES} and no larger
 * than 1280×720. An MP4 whose size KLIPY did not state is refused rather
 * than assumed small.
 */
export function pickKlipyVideo(clip: KlipyClip): KlipyVideoChoice {
  const mp4 = rendition(clip, "mp4", "video/mp4");
  if (!mp4 || !new URL(mp4.url).pathname.toLowerCase().endsWith(".mp4")) {
    return {ok: false, reason: "missing-media"};
  }
  if (mp4.sizeBytes === null) {
    return {ok: false, reason: "unknown-media-size"};
  }
  if (mp4.sizeBytes > MAX_KLIPY_MP4_BYTES) {
    return {ok: false, reason: "oversized-media"};
  }
  if (
    (mp4.width !== null && mp4.width > MAX_KLIPY_VIDEO_WIDTH) ||
    (mp4.height !== null && mp4.height > MAX_KLIPY_VIDEO_HEIGHT)
  ) {
    return {ok: false, reason: "resolution-too-high"};
  }
  return {ok: true, rendition: mp4};
}

/**
 * The clip's own animated preview, used as the poster: the WebP, else the
 * GIF, each only on a KLIPY media host and not above
 * {@link MAX_KLIPY_POSTER_BYTES} when its size is known. KLIPY has no still
 * image; `null` when neither preview qualifies.
 */
export function pickKlipyPoster(clip: KlipyClip): KlipyRendition | null {
  for (const candidate of [
    rendition(clip, "webp", "image/webp"),
    rendition(clip, "gif", "image/gif"),
  ]) {
    if (!candidate) continue;
    if (candidate.sizeBytes !== null && candidate.sizeBytes > MAX_KLIPY_POSTER_BYTES) continue;
    return candidate;
  }
  return null;
}

/** KLIPY's credit for a clip: the provider and the clip's page. It names no uploader. */
export function klipyAttribution(clip: KlipyClip): HumorAttribution {
  return {
    provider: "klipy",
    displayName: null,
    username: null,
    sourceUrl: klipyPageUrl(clip.url),
    verified: false,
  };
}

function tagsOf(clip: KlipyClip, title: string | null): string[] {
  const sent = Array.isArray(clip.tags)
    ? clip.tags.filter((t): t is string => typeof t === "string" && t.trim().length > 0)
    : [];
  const words = sent.length > 0 ? sent : (title ?? "").split(/\s+/);
  return words
    .map((t) => t.toLowerCase().replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, ""))
    .filter((t) => t.length > 2)
    .slice(0, 8);
}

export type KlipyMapOutcome =
  | {ok: true; item: HumorSourceItem}
  | {ok: false; reason: string};

type MapContext = {language: string; query?: string | null};

/** One clips-search result → one "video" source item with its own media. */
export function mapKlipyClip(clip: KlipyClip, ctx: MapContext): KlipyMapOutcome {
  if (!clip || typeof clip !== "object") {
    return {ok: false, reason: "missing-id"};
  }
  // With ads enabled KLIPY mixes `type: "ad"` objects into the results.
  if (clip.type !== "clip") {
    return {ok: false, reason: "not-a-clip"};
  }
  const id = klipyIdOf(clip);
  if (!id) {
    return {ok: false, reason: "missing-id"};
  }
  const video = pickKlipyVideo(clip);
  if (!video.ok) {
    return {ok: false, reason: video.reason};
  }
  const poster = pickKlipyPoster(clip);
  const attribution = klipyAttribution(clip);
  const title = cleanProviderTitle(clip.title);
  const {width, height} = video.rendition;
  return {
    ok: true,
    item: {
      sourceId: id,
      sourceUrl: attribution.sourceUrl,
      type: "video",
      language: ctx.language,
      title,
      rawTitle: typeof clip.title === "string" ? clip.title : null,
      slug: typeof clip.slug === "string" ? clip.slug : null,
      altText: null,
      // KLIPY sends no per-item rating; the request-level filter is the control.
      rating: null,
      isSticker: false,
      tags: tagsOf(clip, title),
      attribution,
      query: ctx.query ?? null,
      queryCategory: null,
      origin: "clip",
      media: {
        downloadUrl: video.rendition.url,
        thumbUrl: poster?.url ?? null,
        previewUrl: null,
        // Not sent by KLIPY, and never guessed.
        durationMs: null,
        aspectRatio: width && height ? Math.round((width / height) * 1000) / 1000 : null,
        textBody: title,
        mimeHint: "video/mp4",
      },
    },
  };
}

// --------------------------------------------------------------------------
// HTTP client
// --------------------------------------------------------------------------

/** The subset of `fetch` this source uses — injectable for tests. */
export type KlipyFetch = (
  url: string,
  init?: {method?: string},
) => Promise<{ok: boolean; status: number; text(): Promise<string>}>;

export type KlipySourceOptions = {
  baseUrl?: string;
  fetchImpl?: KlipyFetch;
};

export type KlipyRawPage = {
  clips: KlipyClip[];
  page: number;
  hasNext: boolean;
};

export type KlipySearchResult = {
  items: HumorSourceItem[];
  /** Provider objects that could not be mapped, by reason. */
  rejected: Record<string, number>;
  /** Provider objects received. */
  received: number;
  page: number;
  hasNext: boolean;
};

function encodeCursor(payload: {query: string; language: string; page: number}): string {
  return Buffer.from(JSON.stringify(payload), "utf8").toString("base64url");
}

function decodeCursor(
  cursor: string | null | undefined,
): {query: string; language: string; page: number} | null {
  if (!cursor) return null;
  try {
    const parsed = JSON.parse(Buffer.from(cursor, "base64url").toString("utf8"));
    return typeof parsed?.query === "string" && Number.isInteger(parsed?.page) ? parsed : null;
  } catch {
    return null;
  }
}

/** KLIPY's `locale` is a country code: Turkey for Turkish, the US otherwise. */
function localeOf(language: string): "tr" | "us" {
  return language.toLowerCase().startsWith("tr") ? "tr" : "us";
}

export class KlipyHumorSource implements HumorContentSource {
  readonly kind = "licensed_api" as const;
  readonly provider = "klipy";
  private readonly baseUrl: string;
  private readonly fetchImpl: KlipyFetch;

  constructor(private readonly apiKey: string, options: KlipySourceOptions = {}) {
    this.baseUrl = options.baseUrl ?? KLIPY_API_BASE;
    this.fetchImpl = options.fetchImpl ?? ((url, init) => fetch(url, init));
  }

  static tryCreate(options: Omit<KlipySourceOptions, "baseUrl"> = {}): KlipyHumorSource | null {
    if (!isKlipyConfigured()) {
      return null;
    }
    const key = resolveKlipyApiKey();
    if (!key) {
      return null;
    }
    return new KlipyHumorSource(key, options);
  }

  /**
   * One clips search. Errors carry the HTTP status only — never the URL,
   * whose path holds the API key.
   */
  async searchClipsRaw(input: {
    query: string;
    language: string;
    limit: number;
    page?: number;
  }): Promise<KlipyRawPage> {
    const page = Math.max(1, Math.floor(input.page ?? 1));
    const perPage = Math.min(
      KLIPY_MAX_PER_PAGE,
      Math.max(KLIPY_MIN_PER_PAGE, Math.floor(input.limit)),
    );
    const url = new URL(`${this.baseUrl}/${encodeURIComponent(this.apiKey)}/clips/search`);
    url.searchParams.set("q", input.query.slice(0, 50));
    url.searchParams.set("page", String(page));
    url.searchParams.set("per_page", String(perPage));
    url.searchParams.set("customer_id", KLIPY_CUSTOMER_ID);
    url.searchParams.set("locale", localeOf(input.language));
    url.searchParams.set("content_filter", KLIPY_CONTENT_FILTER);

    let res: Awaited<ReturnType<KlipyFetch>>;
    try {
      res = await this.fetchImpl(url.toString(), {method: "GET"});
    } catch {
      throw new Error("klipy-network-error");
    }
    if (!res.ok) {
      throw new Error(`klipy-http-${res.status}`);
    }
    let body: unknown;
    try {
      body = parseKlipyJson(await res.text());
    } catch {
      throw new Error("klipy-bad-json");
    }
    const envelope = (body && typeof body === "object" ? body : {}) as {
      result?: unknown;
      data?: {data?: unknown; has_next?: unknown};
    };
    if (envelope.result !== true) {
      throw new Error("klipy-rejected");
    }
    const data = envelope.data?.data;
    return {
      clips: Array.isArray(data) ? (data as KlipyClip[]) : [],
      page,
      hasNext: envelope.data?.has_next === true,
    };
  }

  async searchClips(input: {
    query: string;
    language: string;
    limit: number;
    page?: number;
  }): Promise<KlipySearchResult> {
    const raw = await this.searchClipsRaw(input);
    const items: HumorSourceItem[] = [];
    const rejected: Record<string, number> = {};
    for (const clip of raw.clips) {
      const outcome = mapKlipyClip(clip, {language: input.language, query: input.query});
      if (outcome.ok) {
        items.push(outcome.item);
      } else {
        rejected[outcome.reason] = (rejected[outcome.reason] ?? 0) + 1;
      }
    }
    return {items, rejected, received: raw.clips.length, page: raw.page, hasNext: raw.hasNext};
  }

  async search(input: {
    query: string;
    language: string;
    limit: number;
    cursor?: string | null;
  }): Promise<HumorSourcePage> {
    const page = decodeCursor(input.cursor)?.page ?? 1;
    const result = await this.searchClips({...input, page});
    return {
      items: result.items,
      nextCursor: result.hasNext
        ? encodeCursor({query: input.query, language: input.language, page: page + 1})
        : null,
    };
  }

  async getVideos(input: {
    language: string;
    limit: number;
    cursor?: string | null;
    query?: string;
  }): Promise<HumorSourcePage> {
    return this.search({
      query: input.query ?? (localeOf(input.language) === "tr" ? "komik" : "funny"),
      language: input.language,
      limit: input.limit,
      cursor: input.cursor,
    });
  }

  /** KLIPY is used for clips only. */
  async getImages(): Promise<HumorSourcePage> {
    return {items: [], nextCursor: null};
  }

  async getNextPage(cursor: string): Promise<HumorSourcePage> {
    const decoded = decodeCursor(cursor);
    if (!decoded) {
      return {items: [], nextCursor: null};
    }
    return this.search({
      query: decoded.query,
      language: decoded.language,
      limit: KLIPY_MAX_PER_PAGE,
      cursor,
    });
  }
}
