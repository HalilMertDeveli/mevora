import {isGiphyConfigured, resolveGiphyApiKey} from "./humorApiConfig.js";
import type {
  HumorContentSource,
  HumorSourceItem,
  HumorSourcePage,
} from "./sourceAdapter.js";

/** Turkish-first humor search queries for Giphy lang=tr. */
export const GIPHY_TR_QUERIES = [
  "komik",
  "mizah",
  "meme",
  "komik tepki",
  "kahkaha",
  "absürt",
  "sarkastik",
  "komik kedi",
  "komik köpek",
  "komik reaksiyon",
  "komik video",
  "komik anlar",
  "türk komedi",
  "gülmek",
] as const;

export const GIPHY_EN_QUERIES = [
  "funny short",
  "lol meme",
  "hilarious",
  "comedy sketch",
  "funny animals",
  "fail funny",
  "prank funny",
  "absurd comedy",
  "reaction funny",
] as const;

interface GiphyImageSet {
  url?: string;
  width?: string;
  height?: string;
  mp4?: string;
  webp?: string;
}

interface GiphyGif {
  id: string;
  url?: string;
  title?: string;
  images?: {
    original?: GiphyImageSet;
    downsized?: GiphyImageSet;
    downsized_medium?: GiphyImageSet;
    fixed_height?: GiphyImageSet;
    preview_gif?: GiphyImageSet;
    original_mp4?: GiphyImageSet;
    looping?: GiphyImageSet;
  };
}

function pickMp4(gif: GiphyGif): string | null {
  const images = gif.images;
  if (!images) return null;
  return (
    images.original_mp4?.mp4 ||
    images.fixed_height?.mp4 ||
    images.looping?.mp4 ||
    images.original?.mp4 ||
    null
  );
}

function pickImage(gif: GiphyGif): string | null {
  const images = gif.images;
  if (!images) return null;
  return (
    images.downsized_medium?.url ||
    images.downsized?.url ||
    images.fixed_height?.url ||
    images.original?.url ||
    null
  );
}

function pickThumb(gif: GiphyGif): string | null {
  const images = gif.images;
  if (!images) return null;
  return (
    images.preview_gif?.url ||
    images.fixed_height?.url ||
    images.downsized?.url ||
    null
  );
}

function aspectOf(gif: GiphyGif): number | null {
  const img =
    gif.images?.fixed_height ||
    gif.images?.downsized ||
    gif.images?.original;
  const w = Number(img?.width ?? 0);
  const h = Number(img?.height ?? 0);
  if (w > 0 && h > 0) {
    return w / h;
  }
  return null;
}

function mapGif(gif: GiphyGif, language: string): HumorSourceItem | null {
  const mp4 = pickMp4(gif);
  const image = pickImage(gif);
  if (!mp4 && !image) {
    return null;
  }
  const type = mp4 ? "video" : "meme";
  return {
    sourceId: String(gif.id),
    sourceUrl: gif.url ?? `https://giphy.com/gifs/${gif.id}`,
    type,
    language,
    title: gif.title ?? null,
    tags: (gif.title ?? "")
      .toLowerCase()
      .split(/\s+/)
      .filter((t) => t.length > 2)
      .slice(0, 8),
    media: {
      downloadUrl: mp4 || image!,
      thumbUrl: pickThumb(gif) || image,
      previewUrl: image,
      aspectRatio: aspectOf(gif),
      textBody: gif.title ?? null,
      mimeHint: mp4 ? "video/mp4" : "image/gif",
    },
  };
}

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

export class GiphyHumorSource implements HumorContentSource {
  readonly kind = "licensed_api" as const;
  readonly provider = "giphy";

  constructor(
    private readonly apiKey: string,
    private readonly baseUrl = "https://api.giphy.com/v1",
  ) {}

  static tryCreate(): GiphyHumorSource | null {
    if (!isGiphyConfigured()) {
      return null;
    }
    const key = resolveGiphyApiKey();
    if (!key) {
      return null;
    }
    return new GiphyHumorSource(key);
  }

  private async request(
    path: string,
    params: Record<string, string | number>,
  ): Promise<{data: GiphyGif[]; pagination?: {total_count?: number; count?: number; offset?: number}}> {
    const url = new URL(`${this.baseUrl}${path}`);
    url.searchParams.set("api_key", this.apiKey);
    url.searchParams.set("rating", "pg");
    for (const [k, v] of Object.entries(params)) {
      url.searchParams.set(k, String(v));
    }
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 8000);
    let res: Response;
    try {
      res = await fetch(url, {signal: controller.signal});
    } catch (err) {
      const msg = String(err ?? "");
      if (msg.toLowerCase().includes("abort")) {
        throw new Error("giphy-timeout");
      }
      throw err;
    } finally {
      clearTimeout(timer);
    }
    if (!res.ok) {
      throw new Error(`giphy-http-${res.status}`);
    }
    const body = (await res.json()) as {
      data?: GiphyGif[];
      meta?: {status?: number; msg?: string};
      pagination?: {total_count?: number; count?: number; offset?: number};
    };
    if (body.meta?.status && body.meta.status >= 400) {
      throw new Error(
        `giphy-api-${body.meta.status}:${body.meta.msg ?? "error"}`,
      );
    }
    return {
      data: Array.isArray(body.data) ? body.data : [],
      pagination: body.pagination,
    };
  }

  private queriesFor(language: string): readonly string[] {
    return language.toLowerCase().startsWith("tr")
      ? GIPHY_TR_QUERIES
      : GIPHY_EN_QUERIES;
  }

  private async searchInternal(input: {
    query: string;
    language: string;
    limit: number;
    offset: number;
  }): Promise<HumorSourcePage> {
    const lang = input.language.toLowerCase().startsWith("tr") ? "tr" : "en";
    const body = await this.request("/gifs/search", {
      q: input.query,
      lang,
      limit: Math.min(25, Math.max(1, input.limit)),
      offset: Math.max(0, input.offset),
    });
    const items = (body.data ?? [])
      .map((gif) => mapGif(gif, lang))
      .filter((item): item is HumorSourceItem => item != null);
    const nextOffset = input.offset + items.length;
    const total = body.pagination?.total_count ?? 0;
    const nextCursor =
      nextOffset < total && items.length > 0
        ? encodeCursor({
            mode: "search",
            query: input.query,
            language: lang,
            offset: nextOffset,
          })
        : null;
    return {items, nextCursor};
  }

  async search(input: {
    query: string;
    language: string;
    limit: number;
    cursor?: string | null;
  }): Promise<HumorSourcePage> {
    const decoded = decodeCursor(input.cursor);
    return this.searchInternal({
      query: input.query,
      language: input.language,
      limit: input.limit,
      offset: decoded?.offset ?? 0,
    });
  }

  async getImages(input: {
    language: string;
    limit: number;
    cursor?: string | null;
    query?: string;
  }): Promise<HumorSourcePage> {
    const queries = this.queriesFor(input.language);
    const decoded = decodeCursor(input.cursor);
    const query =
      input.query ||
      decoded?.query ||
      queries[Math.floor(Math.random() * queries.length)];
    return this.searchInternal({
      query,
      language: input.language,
      limit: input.limit,
      offset: decoded?.offset ?? 0,
    });
  }

  async getVideos(input: {
    language: string;
    limit: number;
    cursor?: string | null;
    query?: string;
  }): Promise<HumorSourcePage> {
    // Giphy returns GIFs with MP4 renditions — treat as video when mp4 present.
    const page = await this.getImages(input);
    return {
      items: page.items.filter((i) => i.type === "video" || i.media.mimeHint === "video/mp4"),
      nextCursor: page.nextCursor,
    };
  }

  async getNextPage(cursor: string): Promise<HumorSourcePage> {
    const decoded = decodeCursor(cursor);
    if (!decoded) {
      return {items: [], nextCursor: null};
    }
    return this.searchInternal({
      query: decoded.query,
      language: decoded.language,
      limit: 12,
      offset: decoded.offset,
    });
  }
}
