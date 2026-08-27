/**
 * Provider-agnostic humor content source.
 * Active: YouTube Data API (embed) + Giphy (stream CDN). Tenor disabled.
 * No Instagram/TikTok scraping. Never copy third-party media into Storage.
 */

export type HumorSourceKind = "internal" | "licensed_api";

export interface HumorSourceMedia {
  downloadUrl: string;
  thumbUrl?: string | null;
  previewUrl?: string | null;
  durationMs?: number | null;
  aspectRatio?: number | null;
  textBody?: string | null;
  mimeHint?: "image/gif" | "image/jpeg" | "image/png" | "video/mp4" | string;
  /** YouTube iframe embed — stream/display only. */
  embedUrl?: string | null;
  attributionRequired?: boolean;
}

export interface HumorSourceItem {
  sourceId: string;
  sourceUrl?: string | null;
  type: "image" | "video" | "meme" | "text";
  language: string;
  title?: string | null;
  media: HumorSourceMedia;
  tags?: string[];
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
