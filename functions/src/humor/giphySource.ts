import type {HumorCategory} from "./categories.js";
import {isAllowedMediaUrl} from "./contentValidation.js";
import {isGiphyConfigured, resolveGiphyApiKey} from "./humorApiConfig.js";
import {foldText, foldedWords} from "./providerRelevance.js";
import type {
  HumorContentSource,
  HumorSourceItem,
  HumorSourcePage,
} from "./sourceAdapter.js";
import type {HumorAttribution} from "./types.js";

/**
 * GIPHY licensed-API source.
 *
 * Only the documented GIPHY REST API is called (`/v1/gifs/search`, and
 * `/v1/clips/search` when Clips access is enabled). Nothing is scraped and no
 * media is downloaded server-side: we store the provider's own HTTPS URLs and
 * the client streams them.
 *
 * Every mapped item keeps *its own* media, poster, title and attribution. The
 * caption is the provider's title for that exact item, cleaned — never text
 * we write — and `null` when the provider said nothing meaningful.
 */

// --------------------------------------------------------------------------
// Query families
// --------------------------------------------------------------------------

export type GiphyQueryFamily = {
  /** At most 50 characters (the Clips endpoint's limit; GIF search accepts it). */
  query: string;
  language: "tr" | "en";
  /** The humour dimension this query probes: the primary category signal. */
  category: HumorCategory;
};

/**
 * Intentional searches, Turkish first, English as fallback. Each one asks for
 * reactions, scenes or comedy — never a bare "funny", which is what dragged
 * wallpapers and landscapes into the old catalogue.
 */
export const GIPHY_QUERY_FAMILIES: readonly GiphyQueryFamily[] = [
  {query: "komik tepki", language: "tr", category: "silly"},
  {query: "komik sahne", language: "tr", category: "situational"},
  {query: "dizi komik", language: "tr", category: "situational"},
  {query: "film komik", language: "tr", category: "silly"},
  {query: "komedi", language: "tr", category: "silly"},
  {query: "kahkaha", language: "tr", category: "silly"},
  {query: "şaşkınlık", language: "tr", category: "meme"},
  {query: "sarkazm", language: "tr", category: "sarcasm"},
  {query: "ironi", language: "tr", category: "dry"},
  {query: "türk meme", language: "tr", category: "meme"},
  {query: "sitcom", language: "tr", category: "situational"},
  {query: "funny reaction", language: "en", category: "silly"},
  {query: "comedy reaction", language: "en", category: "situational"},
  {query: "sitcom reaction", language: "en", category: "situational"},
  {query: "funny tv", language: "en", category: "silly"},
  {query: "comedy scene", language: "en", category: "situational"},
  {query: "movie reaction", language: "en", category: "meme"},
  {query: "sarcastic reaction", language: "en", category: "sarcasm"},
  {query: "awkward reaction", language: "en", category: "cringe"},
  {query: "absurd comedy", language: "en", category: "absurd"},
  {query: "dry humor", language: "en", category: "dry"},
  {query: "laughing reaction", language: "en", category: "silly"},
];

/** Kept for callers that only want the query strings. */
export const GIPHY_TR_QUERIES: readonly string[] = GIPHY_QUERY_FAMILIES
  .filter((f) => f.language === "tr")
  .map((f) => f.query);
export const GIPHY_EN_QUERIES: readonly string[] = GIPHY_QUERY_FAMILIES
  .filter((f) => f.language === "en")
  .map((f) => f.query);

function rotate<T>(list: readonly T[], by: number): T[] {
  if (list.length === 0) return [];
  const start = ((Math.floor(by) % list.length) + list.length) % list.length;
  return [...list.slice(start), ...list.slice(0, start)];
}

/**
 * Deterministic query selection: `rotation` (the caller passes e.g. the UTC
 * day number) shifts the starting family, so successive syncs cover different
 * queries without any randomness. Turkish families come first for a Turkish
 * sync; English families follow as fallback. An English sync uses English only.
 */
export function selectQueryFamilies(
  language: string,
  count: number,
  rotation = 0,
): GiphyQueryFamily[] {
  const tr = GIPHY_QUERY_FAMILIES.filter((f) => f.language === "tr");
  const en = GIPHY_QUERY_FAMILIES.filter((f) => f.language === "en");
  const ordered = language.toLowerCase().startsWith("tr")
    ? [...rotate(tr, rotation), ...rotate(en, rotation)]
    : rotate(en, rotation);
  return ordered.slice(0, Math.max(0, Math.floor(count)));
}

// --------------------------------------------------------------------------
// Provider payload shapes (standard GIPHY API)
// --------------------------------------------------------------------------

type Numeric = string | number | undefined | null;

interface GiphyRendition {
  url?: string;
  width?: Numeric;
  height?: Numeric;
  mp4?: string;
  mp4_size?: Numeric;
  size?: Numeric;
  webp?: string;
  webp_size?: Numeric;
}

interface GiphyImages {
  original?: GiphyRendition;
  original_mp4?: GiphyRendition;
  fixed_height?: GiphyRendition;
  fixed_width?: GiphyRendition;
  fixed_height_small?: GiphyRendition;
  fixed_width_small?: GiphyRendition;
  fixed_height_downsampled?: GiphyRendition;
  fixed_width_downsampled?: GiphyRendition;
  downsized_small?: GiphyRendition;
  downsized_medium?: GiphyRendition;
  fixed_height_still?: GiphyRendition;
  original_still?: GiphyRendition;
}

interface GiphyUser {
  username?: string;
  display_name?: string;
  is_verified?: boolean;
  profile_url?: string;
}

export interface GiphyGif {
  id: string;
  type?: string;
  url?: string;
  slug?: string;
  title?: string;
  username?: string;
  source_tld?: string;
  rating?: string;
  alt_text?: string;
  is_sticker?: number | boolean;
  user?: GiphyUser;
  images?: GiphyImages;
}

interface GiphyClipAsset {
  url?: string;
  width?: Numeric;
  height?: Numeric;
}

export interface GiphyClip extends GiphyGif {
  video?: {
    assets?: Record<string, GiphyClipAsset | undefined>;
    duration?: Numeric;
    description?: string;
  };
}

// --------------------------------------------------------------------------
// Rendition, poster, attribution and caption selection (pure)
// --------------------------------------------------------------------------

/** Largest MP4 we prefer to hand a phone's video_player (~2.5 MB). */
export const MAX_MP4_BYTES = 2_500_000;

export type SelectedRendition = {
  name: string;
  url: string;
  width: number | null;
  height: number | null;
  sizeBytes: number | null;
};

function num(value: Numeric): number | null {
  if (value === undefined || value === null || value === "") return null;
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? n : null;
}

/**
 * Best H.264 MP4 for mobile playback among `original_mp4`, `fixed_height.mp4`
 * and `downsized_small.mp4`:
 * - the highest-resolution one whose `mp4_size` is known and ≤ MAX_MP4_BYTES;
 * - otherwise the smallest one with a known size;
 * - otherwise (no sizes at all) the one expected to be smallest.
 * Only HTTPS URLs on an allowed host are considered.
 */
export function pickGifRendition(images: GiphyImages | undefined | null): SelectedRendition | null {
  if (!images) return null;
  const candidates: SelectedRendition[] = [
    ["original_mp4", images.original_mp4],
    ["fixed_height", images.fixed_height],
    ["downsized_small", images.downsized_small],
  ]
    .map(([name, r]) => {
      const rendition = r as GiphyRendition | undefined;
      return {
        name: name as string,
        url: rendition?.mp4 ?? "",
        width: num(rendition?.width),
        height: num(rendition?.height),
        sizeBytes: num(rendition?.mp4_size),
      };
    })
    .filter((c) => isAllowedMediaUrl(c.url));
  if (candidates.length === 0) return null;

  const area = (c: SelectedRendition) => (c.width ?? 0) * (c.height ?? 0);
  const fits = candidates.filter((c) => c.sizeBytes !== null && c.sizeBytes <= MAX_MP4_BYTES);
  if (fits.length > 0) {
    return fits.reduce((best, c) => (area(c) > area(best) ? c : best));
  }
  const sized = candidates.filter((c) => c.sizeBytes !== null);
  if (sized.length > 0) {
    return sized.reduce((best, c) => (c.sizeBytes! < best.sizeBytes! ? c : best));
  }
  // No sizes reported: the renditions are listed largest-first, so the last
  // available one is the lightest bet.
  return candidates[candidates.length - 1];
}

/** Largest original animated WebP we hand a full-width phone card (1.5 MB). */
export const MAX_ORIGINAL_WEBP_BYTES = 1_500_000;

export type SelectedImageRendition = SelectedRendition & {
  mimeHint: "image/webp" | "image/gif";
};

/** Renditions that may carry an animated WebP, largest first. */
const WEBP_RENDITIONS = [
  "original",
  "fixed_width",
  "fixed_height",
  "fixed_width_downsampled",
  "fixed_height_downsampled",
  "fixed_width_small",
  "fixed_height_small",
] as const;

function webpOf(
  images: GiphyImages,
  name: (typeof WEBP_RENDITIONS)[number],
): SelectedImageRendition | null {
  const rendition = images[name];
  const url = rendition?.webp ?? "";
  if (!isAllowedMediaUrl(url)) return null;
  return {
    name: `${name}.webp`,
    url,
    width: num(rendition?.width),
    height: num(rendition?.height),
    sizeBytes: num(rendition?.webp_size),
    mimeHint: "image/webp",
  };
}

/**
 * The animated-image rendition a GIF is shown as (Flutter decodes and loops
 * animated WebP/GIF in its own image pipeline; no video player involved):
 * 1. `original.webp` when its `webp_size` is known and ≤ MAX_ORIGINAL_WEBP_BYTES;
 * 2. else `downsized_medium.url` (an animated GIF GIPHY keeps small);
 * 3. else the wider of `fixed_width.webp` / `fixed_height.webp`;
 * 4. else the smallest known WebP of any other rendition.
 * Only HTTPS URLs on an allowed host are considered. `null` means the item
 * has no animated-image rendition at all (the caller may fall back to MP4).
 */
export function pickGifImageRendition(
  images: GiphyImages | undefined | null,
): SelectedImageRendition | null {
  if (!images) return null;

  const original = webpOf(images, "original");
  if (original && original.sizeBytes !== null && original.sizeBytes <= MAX_ORIGINAL_WEBP_BYTES) {
    return original;
  }

  const medium = images.downsized_medium;
  if (medium && isAllowedMediaUrl(medium.url)) {
    return {
      name: "downsized_medium",
      url: medium.url!,
      width: num(medium.width),
      height: num(medium.height),
      sizeBytes: num(medium.size),
      mimeHint: "image/gif",
    };
  }

  const fixed = [webpOf(images, "fixed_width"), webpOf(images, "fixed_height")]
    .filter((c): c is SelectedImageRendition => c !== null);
  if (fixed.length > 0) {
    return fixed.reduce((best, c) => ((c.width ?? 0) > (best.width ?? 0) ? c : best));
  }

  const rest = WEBP_RENDITIONS
    .map((name) => webpOf(images, name))
    .filter((c): c is SelectedImageRendition => c !== null);
  if (rest.length === 0) return null;
  const sized = rest.filter((c) => c.sizeBytes !== null);
  if (sized.length > 0) {
    return sized.reduce((best, c) => (c.sizeBytes! < best.sizeBytes! ? c : best));
  }
  // No sizes reported: listed largest-first, so the last is the lightest bet.
  return rest[rest.length - 1];
}

/** Last two path segments (`<id>/<file>`) of an allowed HTTPS URL, lowercased. */
export function mediaPathKey(raw: string | null | undefined): string | null {
  if (!raw || !isAllowedMediaUrl(raw)) return null;
  try {
    const parts = new URL(raw).pathname.split("/").filter(Boolean);
    return parts.length >= 2 ? parts.slice(-2).join("/").toLowerCase() : null;
  } catch {
    return null;
  }
}

/**
 * `<id>/<file>` of every GIF MP4 rendition of this item. The host (CDN shard)
 * and the query string (`cid`, …) vary between API responses; the tail does
 * not. Used only to recognise a doc stored before GIFs became images.
 */
export function gifMp4Keys(images: GiphyImages | undefined | null): string[] {
  if (!images) return [];
  const keys = new Set<string>();
  for (const rendition of Object.values(images) as Array<GiphyRendition | undefined>) {
    const key = mediaPathKey(rendition?.mp4);
    if (key) keys.add(key);
  }
  return [...keys];
}

/** Clip renditions in preference order: moderate first, never 1080p / 4k. */
export const CLIP_RENDITION_ORDER = ["480p", "360p", "720p"] as const;

export function pickClipRendition(clip: GiphyClip | null | undefined): SelectedRendition | null {
  const assets = clip?.video?.assets;
  if (!assets) return null;
  for (const name of CLIP_RENDITION_ORDER) {
    const asset = assets[name];
    if (asset && isAllowedMediaUrl(asset.url)) {
      return {
        name,
        url: asset.url!,
        width: num(asset.width),
        height: num(asset.height),
        sizeBytes: null,
      };
    }
  }
  return null;
}

/** A real still frame of the same item: `fixed_height_still`, else `original_still`. */
export function pickPoster(images: GiphyImages | undefined | null): string | null {
  for (const url of [images?.fixed_height_still?.url, images?.original_still?.url]) {
    if (url && isAllowedMediaUrl(url)) {
      return url;
    }
  }
  return null;
}

function aspectOf(rendition: SelectedRendition, images: GiphyImages | undefined): number | null {
  const w = rendition.width ?? num(images?.original?.width);
  const h = rendition.height ?? num(images?.original?.height);
  return w && h ? w / h : null;
}

function giphyPageUrl(raw: string | undefined): string | null {
  if (!raw) return null;
  try {
    const url = new URL(raw);
    const host = url.hostname.toLowerCase();
    if (url.protocol === "https:" && (host === "giphy.com" || host.endsWith(".giphy.com"))) {
      return url.toString();
    }
  } catch {
    // fall through
  }
  return null;
}

function cleanName(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.replace(/\s+/g, " ").trim();
  return trimmed ? trimmed.slice(0, 80) : null;
}

/** The provider's own credit for an item. Nothing here is invented. */
export function giphyAttribution(item: GiphyGif): HumorAttribution {
  return {
    provider: "giphy",
    displayName: cleanName(item.user?.display_name),
    username: cleanName(item.user?.username) ?? cleanName(item.username),
    sourceUrl: giphyPageUrl(item.url),
    verified: item.user?.is_verified === true,
  };
}

const GENERIC_TITLES = new Set([
  "gif", "gifs", "sticker", "stickers", "video", "clip", "clips", "untitled",
  "no title", "giphy", "null", "undefined", "image", "animated gif",
]);

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export const MAX_CAPTION_LENGTH = 200;

/**
 * The provider title as a caption, or `null`.
 *
 * Strips the provider's boilerplate — a trailing " GIF", " GIF by <user>",
 * " Sticker by <user>", or "by <this item's user>" — and collapses
 * whitespace. A title that is then empty, generic ("GIF", "untitled") or just
 * the uploader's name says nothing about the item and becomes `null`. Text is
 * only ever removed, never added.
 */
export function cleanProviderTitle(
  raw: unknown,
  who: {username?: string | null; displayName?: string | null} = {},
): string | null {
  if (typeof raw !== "string") return null;
  let title = raw.replace(/\s+/g, " ").trim();
  title = title.replace(/\s*\b(?:gif|gifs|sticker|stickers)\s+by\s+.*$/i, "");
  for (const name of [who.username, who.displayName]) {
    if (name && name.trim()) {
      title = title.replace(new RegExp(`\\s+by\\s+@?${escapeRegExp(name.trim())}\\s*$`, "i"), "");
    }
  }
  title = title
    .replace(/\s+(?:gif|gifs|sticker|stickers)$/i, "")
    .replace(/[\s\-–—|:,]+$/, "")
    .replace(/\s+/g, " ")
    .trim();
  if (!title) return null;
  const compact = foldText(title).replace(/[^a-z0-9]/g, "");
  if (!compact) return null;
  if (GENERIC_TITLES.has(foldText(title))) return null;
  for (const name of [who.username, who.displayName]) {
    if (name && foldText(name).replace(/[^a-z0-9]/g, "") === compact) return null;
  }
  return title.length > MAX_CAPTION_LENGTH ? title.slice(0, MAX_CAPTION_LENGTH).trim() : title;
}

function tagsFrom(title: string | null): string[] {
  if (!title) return [];
  return title
    .toLowerCase()
    .split(/\s+/)
    .map((t) => t.replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, ""))
    .filter((t) => t.length > 2)
    .slice(0, 8);
}

export type GiphyMapOutcome =
  | {ok: true; item: HumorSourceItem}
  | {ok: false; reason: string};

type MapContext = {language: string; family?: GiphyQueryFamily | null};

function mapCommon(
  raw: GiphyGif,
  rendition: SelectedRendition,
  ctx: MapContext,
  origin: "gif" | "clip",
  durationMs: number | null,
  as: {type: "video" | "meme"; mimeHint: string} = {type: "video", mimeHint: "video/mp4"},
): HumorSourceItem {
  const attribution = giphyAttribution(raw);
  const title = cleanProviderTitle(raw.title, attribution);
  return {
    sourceId: String(raw.id),
    sourceUrl: attribution.sourceUrl,
    type: as.type,
    language: ctx.language,
    title,
    rawTitle: typeof raw.title === "string" ? raw.title : null,
    slug: typeof raw.slug === "string" ? raw.slug : null,
    altText: typeof raw.alt_text === "string" ? raw.alt_text : null,
    rating: typeof raw.rating === "string" ? raw.rating : null,
    isSticker: raw.is_sticker === 1 || raw.is_sticker === true || raw.type === "sticker",
    tags: tagsFrom(title),
    attribution,
    query: ctx.family?.query ?? null,
    queryCategory: ctx.family?.category ?? null,
    origin,
    media: {
      downloadUrl: rendition.url,
      thumbUrl: pickPoster(raw.images),
      previewUrl: null,
      durationMs,
      aspectRatio: aspectOf(rendition, raw.images),
      textBody: title,
      mimeHint: as.mimeHint,
    },
  };
}

/**
 * One GIF search result → one source item, with its own media and title.
 *
 * A GIF is a silent short loop — an image, not a video — so it is stored as a
 * "meme" whose media is an animated WebP/GIF (see pickGifImageRendition) and
 * the client shows it through its image pipeline. Only a GIF with no
 * animated-image rendition at all falls back to its MP4 as a "video".
 */
export function mapGiphyGif(gif: GiphyGif, ctx: MapContext): GiphyMapOutcome {
  if (!gif || typeof gif !== "object" || !gif.id) {
    return {ok: false, reason: "missing-id"};
  }
  const legacyVideoKeys = gifMp4Keys(gif.images);
  const image = pickGifImageRendition(gif.images);
  if (image) {
    const item = mapCommon(gif, image, ctx, "gif", null, {type: "meme", mimeHint: image.mimeHint});
    return {ok: true, item: {...item, legacyVideoKeys}};
  }
  const rendition = pickGifRendition(gif.images);
  if (!rendition) {
    return {ok: false, reason: "missing-media"};
  }
  return {ok: true, item: {...mapCommon(gif, rendition, ctx, "gif", null), legacyVideoKeys}};
}

/** One Clips search result → one source item (480p, else 360p). */
export function mapGiphyClip(clip: GiphyClip, ctx: MapContext): GiphyMapOutcome {
  if (!clip || typeof clip !== "object" || !clip.id) {
    return {ok: false, reason: "missing-id"};
  }
  const rendition = pickClipRendition(clip);
  if (!rendition) {
    return {ok: false, reason: "missing-media"};
  }
  const seconds = num(clip.video?.duration);
  return {
    ok: true,
    item: mapCommon(clip, rendition, ctx, "clip", seconds ? Math.round(seconds * 1000) : null),
  };
}

// --------------------------------------------------------------------------
// HTTP client
// --------------------------------------------------------------------------

/** The subset of `fetch` this source uses — injectable for tests. */
export type GiphyFetch = (
  url: string,
  init?: {method?: string},
) => Promise<{ok: boolean; status: number; json(): Promise<unknown>}>;

export type GiphySearchResult = {
  items: HumorSourceItem[];
  /** Provider objects that could not be mapped, by reason. */
  rejected: Record<string, number>;
  /** Provider objects received. */
  received: number;
  total: number | null;
};

export type GiphyClipsResult = GiphySearchResult & {
  /** False when Clips is disabled or the key has no Clips access. */
  available: boolean;
};

export type GiphySourceOptions = {
  baseUrl?: string;
  fetchImpl?: GiphyFetch;
  /** Call /v1/clips/search at all. Needs GIPHY approval; off by default. */
  clipsEnabled?: boolean;
  /** Upper content rating requested from the API. */
  rating?: "g" | "pg" | "pg-13";
};

/** Clips access denied or not provisioned: fall back to GIF search quietly. */
const CLIPS_UNAVAILABLE_STATUSES = new Set([401, 403, 404]);

function encodeCursor(payload: {
  mode: string;
  query: string;
  language: string;
  offset: number;
}): string {
  return Buffer.from(JSON.stringify(payload), "utf8").toString("base64url");
}

function decodeCursor(cursor: string | null | undefined): {
  mode: string;
  query: string;
  language: string;
  offset: number;
} | null {
  if (!cursor) return null;
  try {
    return JSON.parse(Buffer.from(cursor, "base64url").toString("utf8"));
  } catch {
    return null;
  }
}

function langOf(language: string): "tr" | "en" {
  return language.toLowerCase().startsWith("tr") ? "tr" : "en";
}

export class GiphyHumorSource implements HumorContentSource {
  readonly kind = "licensed_api" as const;
  readonly provider = "giphy";
  private readonly baseUrl: string;
  private readonly fetchImpl: GiphyFetch;
  readonly clipsEnabled: boolean;
  private readonly rating: string;

  constructor(private readonly apiKey: string, options: GiphySourceOptions = {}) {
    this.baseUrl = options.baseUrl ?? "https://api.giphy.com/v1";
    this.fetchImpl = options.fetchImpl ?? ((url, init) => fetch(url, init));
    this.clipsEnabled = options.clipsEnabled === true;
    this.rating = options.rating ?? "pg";
  }

  static tryCreate(options: Omit<GiphySourceOptions, "baseUrl"> = {}): GiphyHumorSource | null {
    if (!isGiphyConfigured()) {
      return null;
    }
    const key = resolveGiphyApiKey();
    if (!key) {
      return null;
    }
    return new GiphyHumorSource(key, options);
  }

  /**
   * One API call. Errors carry the HTTP status only — never the URL, which
   * holds the API key.
   */
  private async request(
    path: string,
    params: Record<string, string | number>,
  ): Promise<{status: number; ok: boolean; body: Record<string, unknown> | null}> {
    const url = new URL(`${this.baseUrl}${path}`);
    url.searchParams.set("api_key", this.apiKey);
    url.searchParams.set("rating", this.rating);
    for (const [k, v] of Object.entries(params)) {
      url.searchParams.set(k, String(v));
    }
    let res: Awaited<ReturnType<GiphyFetch>>;
    try {
      res = await this.fetchImpl(url.toString(), {method: "GET"});
    } catch {
      throw new Error("giphy-network-error");
    }
    if (!res.ok) {
      return {status: res.status, ok: false, body: null};
    }
    let body: unknown;
    try {
      body = await res.json();
    } catch {
      throw new Error("giphy-bad-json");
    }
    return {
      status: res.status,
      ok: true,
      body: body && typeof body === "object" ? (body as Record<string, unknown>) : null,
    };
  }

  private collect<T>(
    body: Record<string, unknown> | null,
    map: (raw: T) => GiphyMapOutcome,
  ): GiphySearchResult {
    const data = Array.isArray(body?.data) ? (body!.data as T[]) : [];
    const items: HumorSourceItem[] = [];
    const rejected: Record<string, number> = {};
    for (const raw of data) {
      const outcome = map(raw);
      if (outcome.ok) {
        items.push(outcome.item);
      } else {
        rejected[outcome.reason] = (rejected[outcome.reason] ?? 0) + 1;
      }
    }
    const pagination = body?.pagination as {total_count?: unknown} | undefined;
    const total = Number(pagination?.total_count);
    return {
      items,
      rejected,
      received: data.length,
      total: Number.isFinite(total) ? total : null,
    };
  }

  private async gifSearchBody(input: {
    query: string;
    language: string;
    limit: number;
    offset?: number;
  }): Promise<Record<string, unknown> | null> {
    const res = await this.request("/gifs/search", {
      q: input.query.slice(0, 50),
      lang: langOf(input.language),
      limit: Math.min(50, Math.max(1, Math.floor(input.limit))),
      offset: Math.max(0, Math.floor(input.offset ?? 0)),
    });
    if (!res.ok) {
      throw new Error(`giphy-http-${res.status}`);
    }
    return res.body;
  }

  async searchGifs(input: {
    query: string;
    language: string;
    limit: number;
    offset?: number;
    family?: GiphyQueryFamily | null;
  }): Promise<GiphySearchResult> {
    const lang = langOf(input.language);
    const body = await this.gifSearchBody(input);
    return this.collect<GiphyGif>(body, (gif) =>
      mapGiphyGif(gif, {language: lang, family: input.family ?? null}),
    );
  }

  /**
   * The provider's GIF objects for a search, unmapped: the curator tool needs
   * rendition sizes and dimensions that mapping deliberately drops.
   */
  async searchGifsRaw(input: {
    query: string;
    language: string;
    limit: number;
    offset?: number;
  }): Promise<{gifs: GiphyGif[]; total: number | null}> {
    const body = await this.gifSearchBody(input);
    const gifs = Array.isArray(body?.data)
      ? (body!.data as unknown[]).filter(
          (g): g is GiphyGif => !!g && typeof g === "object" && !Array.isArray(g),
        )
      : [];
    const pagination = body?.pagination as {total_count?: unknown} | undefined;
    const total = Number(pagination?.total_count);
    return {gifs, total: Number.isFinite(total) ? total : null};
  }

  /**
   * Clips search. Returns `available: false` — never throws — when Clips is
   * not enabled here or GIPHY answers 401/403/404 (no Clips access), so the
   * caller falls back to GIF search.
   */
  async searchClips(input: {
    query: string;
    language: string;
    limit: number;
    offset?: number;
    family?: GiphyQueryFamily | null;
  }): Promise<GiphyClipsResult> {
    const empty = {items: [], rejected: {}, received: 0, total: null};
    if (!this.clipsEnabled) {
      return {...empty, available: false};
    }
    const lang = langOf(input.language);
    const res = await this.request("/clips/search", {
      q: input.query.slice(0, 50),
      lang,
      limit: Math.min(50, Math.max(1, Math.floor(input.limit))),
      offset: Math.max(0, Math.floor(input.offset ?? 0)),
    });
    if (!res.ok) {
      if (CLIPS_UNAVAILABLE_STATUSES.has(res.status)) {
        return {...empty, available: false};
      }
      throw new Error(`giphy-clips-http-${res.status}`);
    }
    return {
      ...this.collect<GiphyClip>(res.body, (clip) =>
        mapGiphyClip(clip, {language: lang, family: input.family ?? null}),
      ),
      available: true,
    };
  }

  // ----- HumorContentSource ------------------------------------------------

  private async page(query: string, language: string, limit: number, offset: number) {
    const lang = langOf(language);
    const family =
      GIPHY_QUERY_FAMILIES.find((f) => f.query === query && f.language === lang) ?? null;
    const result = await this.searchGifs({query, language: lang, limit, offset, family});
    const nextOffset = offset + result.received;
    const nextCursor =
      result.total !== null && nextOffset < result.total && result.received > 0
        ? encodeCursor({mode: "search", query, language: lang, offset: nextOffset})
        : null;
    return {items: result.items, nextCursor};
  }

  async search(input: {
    query: string;
    language: string;
    limit: number;
    cursor?: string | null;
  }): Promise<HumorSourcePage> {
    const decoded = decodeCursor(input.cursor);
    return this.page(input.query, input.language, input.limit, decoded?.offset ?? 0);
  }

  async getImages(input: {
    language: string;
    limit: number;
    cursor?: string | null;
    query?: string;
  }): Promise<HumorSourcePage> {
    const decoded = decodeCursor(input.cursor);
    // Deterministic: an explicit query, the cursor's query, or the first family.
    const query =
      input.query ||
      decoded?.query ||
      selectQueryFamilies(input.language, 1)[0]?.query ||
      GIPHY_QUERY_FAMILIES[0].query;
    return this.page(query, input.language, input.limit, decoded?.offset ?? 0);
  }

  async getVideos(input: {
    language: string;
    limit: number;
    cursor?: string | null;
    query?: string;
  }): Promise<HumorSourcePage> {
    // GIF search: animated images, with an MP4 only where no image exists.
    return this.getImages(input);
  }

  async getNextPage(cursor: string): Promise<HumorSourcePage> {
    const decoded = decodeCursor(cursor);
    if (!decoded) {
      return {items: [], nextCursor: null};
    }
    return this.page(decoded.query, decoded.language, 12, decoded.offset);
  }
}

/** Folded title + uploader: the within-batch "same thing twice" key. */
export function titleIdentityKey(item: HumorSourceItem): string | null {
  const title = foldedWords(item.title).join(" ");
  if (!title) return null;
  const who = foldText(item.attribution?.username ?? "").replace(/[^a-z0-9]/g, "");
  return `${title}|${who}`;
}
