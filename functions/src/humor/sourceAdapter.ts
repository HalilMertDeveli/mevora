/**
 * Provider-agnostic humor content source.
 * MVP provider: Giphy (licensed API). No Instagram/TikTok/YouTube scraping.
 */
import type {HumorCategory} from "./categories.js";
import type {HumorAttribution} from "./types.js";

export type HumorSourceKind = "internal" | "licensed_api";

export interface HumorSourceMedia {
  downloadUrl: string;
  thumbUrl?: string | null;
  previewUrl?: string | null;
  durationMs?: number | null;
  aspectRatio?: number | null;
  textBody?: string | null;
  mimeHint?: "image/gif" | "image/jpeg" | "image/png" | "video/mp4" | string;
}

export interface HumorSourceItem {
  sourceId: string;
  sourceUrl?: string | null;
  type: "image" | "video" | "meme" | "text";
  language: string;
  /** Cleaned provider title (never invented); null when it said nothing. */
  title?: string | null;
  media: HumorSourceMedia;
  tags?: string[];
  /** Provider content rating as sent (e.g. "g", "pg", "pg-13"). */
  rating?: string | null;
  /** Raw provider text the relevance filter reads; never shown to users. */
  slug?: string | null;
  altText?: string | null;
  rawTitle?: string | null;
  /** Transparent sticker rather than a scene. */
  isSticker?: boolean;
  /** Who made it — stored as the K1 attribution. */
  attribution?: HumorAttribution | null;
  /** The query that found it and the humor category that query probes. */
  query?: string | null;
  queryCategory?: HumorCategory | null;
  /** "gif" or "clip" — which provider endpoint produced it. */
  origin?: "gif" | "clip";
}

export interface HumorSourcePage {
  items: HumorSourceItem[];
  nextCursor: string | null;
}

export interface HumorContentSource {
  readonly kind: HumorSourceKind;
  readonly provider: string;
  getVideos(input: {
    language: string;
    limit: number;
    cursor?: string | null;
    query?: string;
  }): Promise<HumorSourcePage>;
  getImages(input: {
    language: string;
    limit: number;
    cursor?: string | null;
    query?: string;
  }): Promise<HumorSourcePage>;
  getNextPage(cursor: string): Promise<HumorSourcePage>;
  search(input: {
    query: string;
    language: string;
    limit: number;
    cursor?: string | null;
  }): Promise<HumorSourcePage>;
}

export class InternalHumorSourceAdapter implements HumorContentSource {
  readonly kind = "internal" as const;
  readonly provider = "mevora-internal";

  async getVideos(): Promise<HumorSourcePage> {
    return {items: [], nextCursor: null};
  }
  async getImages(): Promise<HumorSourcePage> {
    return {items: [], nextCursor: null};
  }
  async getNextPage(): Promise<HumorSourcePage> {
    return {items: [], nextCursor: null};
  }
  async search(): Promise<HumorSourcePage> {
    return {items: [], nextCursor: null};
  }
}

/** Stub shell for alternate licensed providers (Tenor, etc.). */
export class LicensedApiHumorSourceAdapter implements HumorContentSource {
  readonly kind = "licensed_api" as const;
  constructor(readonly provider: string) {}

  async getVideos(): Promise<HumorSourcePage> {
    return {items: [], nextCursor: null};
  }
  async getImages(): Promise<HumorSourcePage> {
    return {items: [], nextCursor: null};
  }
  async getNextPage(): Promise<HumorSourcePage> {
    return {items: [], nextCursor: null};
  }
  async search(): Promise<HumorSourcePage> {
    return {items: [], nextCursor: null};
  }
}

export function resolveHumorSourceAdapter(
  kind: HumorSourceKind = "internal",
  provider = "mevora-internal",
): HumorContentSource {
  if (kind === "licensed_api") {
    return new LicensedApiHumorSourceAdapter(provider);
  }
  return new InternalHumorSourceAdapter();
}
