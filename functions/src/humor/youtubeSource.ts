import {isYoutubeConfigured, resolveYoutubeDataApiKey} from "./humorApiConfig.js";
import {
  BUCKET_TO_CATEGORY,
  type HumorSearchBucket,
  pickBucketQuery,
} from "./categoryQueries.js";
import {
  contentIdFromProvider,
  type NormalizedHumorContent,
} from "./normalizedContent.js";
import type {
  HumorContentSource,
  HumorSourceItem,
  HumorSourcePage,
} from "./sourceAdapter.js";

interface YoutubeSearchItem {
  id?: {videoId?: string};
  snippet?: {
    title?: string;
    description?: string;
    channelTitle?: string;
    publishedAt?: string;
    thumbnails?: {
      medium?: {url?: string};
      high?: {url?: string};
      default?: {url?: string};
    };
  };
}

interface YoutubeSearchResponse {
  items?: YoutubeSearchItem[];
  nextPageToken?: string;
  error?: {message?: string; errors?: Array<{reason?: string}>};
}

const NSFW_BLOCK =
  /\b(nsfw|porn|xxx|sex|nude|naked|erotik|pornografi|gore|kill|murder|suicide)\b/i;

export function youtubeEmbedUrl(videoId: string): string {
  return `https://www.youtube.com/embed/${encodeURIComponent(videoId)}?playsinline=1&rel=0&modestbranding=1`;
}

export function youtubeWatchUrl(videoId: string): string {
  return `https://www.youtube.com/watch?v=${encodeURIComponent(videoId)}`;
}

export function youtubeThumbUrl(videoId: string): string {
  return `https://i.ytimg.com/vi/${encodeURIComponent(videoId)}/hqdefault.jpg`;
}

export function mapYoutubeItem(
  item: YoutubeSearchItem,
  language: string,
  bucket: HumorSearchBucket,
): NormalizedHumorContent | null {
  const videoId = item.id?.videoId?.trim();
  if (!videoId) {
    return null;
  }
  const title = (item.snippet?.title ?? "").trim() || "YouTube";
  if (NSFW_BLOCK.test(title) || NSFW_BLOCK.test(item.snippet?.description ?? "")) {
    return null;
  }
  const thumb =
    item.snippet?.thumbnails?.high?.url ||
    item.snippet?.thumbnails?.medium?.url ||
    item.snippet?.thumbnails?.default?.url ||
    youtubeThumbUrl(videoId);
  const tags = title
    .toLowerCase()
    .split(/\s+/)
    .filter((t) => t.length > 2)
    .slice(0, 8);
  return {
    id: contentIdFromProvider("youtube", videoId),
    provider: "youtube",
    providerContentId: videoId,
    type: "video",
    title,
    thumbnailUrl: thumb,
    contentUrl: null,
    embedUrl: youtubeEmbedUrl(videoId),
    durationMs: null,
    category: BUCKET_TO_CATEGORY[bucket],
    language,
    tags: [...tags, bucket, "youtube"],
    sourceUrl: youtubeWatchUrl(videoId),
    attributionRequired: true,
    createdAt: item.snippet?.publishedAt ?? new Date().toISOString(),
  };
}

export function normalizedToSourceItem(
  item: NormalizedHumorContent,
): HumorSourceItem | null {
  // YouTube: stream via embed only — use embed as media URL marker for ingest.
  const downloadUrl = item.contentUrl || item.embedUrl;
  if (!downloadUrl) {
    return null;
  }
  return {
    sourceId: item.providerContentId,
    sourceUrl: item.sourceUrl,
    type: item.type === "gif" ? "meme" : "video",
    language: item.language,
    title: item.title,
    tags: item.tags,
    media: {
      downloadUrl,
      thumbUrl: item.thumbnailUrl,
      previewUrl: item.thumbnailUrl,
      durationMs: item.durationMs,
      textBody: item.title,
      mimeHint: item.type === "gif" ? "image/gif" : "video/mp4",
      embedUrl: item.embedUrl,
      attributionRequired: item.attributionRequired,
    },
  };
}

export class YoutubeHumorSource implements HumorContentSource {
  readonly kind = "licensed_api" as const;
  readonly provider = "youtube";

  constructor(
    private readonly apiKey: string,
    private readonly baseUrl = "https://www.googleapis.com/youtube/v3",
  ) {}

  static tryCreate(): YoutubeHumorSource | null {
    if (!isYoutubeConfigured()) {
      return null;
    }
    const key = resolveYoutubeDataApiKey();
    if (!key) {
      return null;
    }
    return new YoutubeHumorSource(key);
  }

  private async searchInternal(input: {
    query: string;
    language: string;
    limit: number;
    pageToken?: string | null;
    bucket: HumorSearchBucket;
  }): Promise<{
    normalized: NormalizedHumorContent[];
    nextCursor: string | null;
  }> {
    const url = new URL(`${this.baseUrl}/search`);
    url.searchParams.set("key", this.apiKey);
    url.searchParams.set("part", "snippet");
    url.searchParams.set("type", "video");
    url.searchParams.set("q", input.query);
    url.searchParams.set("maxResults", String(Math.min(15, Math.max(1, input.limit))));
    url.searchParams.set("safeSearch", "strict");
    url.searchParams.set("videoEmbeddable", "true");
    url.searchParams.set("videoSyndicated", "true");
    url.searchParams.set("videoDuration", "short");
    url.searchParams.set(
      "relevanceLanguage",
      input.language.toLowerCase().startsWith("tr") ? "tr" : "en",
    );
    if (input.pageToken) {
      url.searchParams.set("pageToken", input.pageToken);
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 8000);
    let res: Response;
    try {
      res = await fetch(url, {signal: controller.signal});
    } finally {
      clearTimeout(timer);
    }

    if (res.status === 403 || res.status === 401) {
      throw new Error("youtube-invalid-or-forbidden");
    }
    if (res.status === 429) {
      throw new Error("youtube-rate-limit");
    }
    if (!res.ok) {
      throw new Error(`youtube-http-${res.status}`);
    }

    const body = (await res.json()) as YoutubeSearchResponse;
    if (body.error) {
      const reason = body.error.errors?.[0]?.reason ?? body.error.message ?? "error";
      throw new Error(`youtube-api-${reason}`);
    }

    const normalized = (body.items ?? [])
      .map((item) => mapYoutubeItem(item, input.language, input.bucket))
      .filter((item): item is NormalizedHumorContent => item != null);

    return {
      normalized,
      nextCursor: body.nextPageToken ?? null,
    };
  }

  async searchByBucket(input: {
    bucket: HumorSearchBucket;
    language: string;
    limit: number;
    cursor?: string | null;
  }): Promise<{
    normalized: NormalizedHumorContent[];
    nextCursor: string | null;
    query: string;
  }> {
    const query = pickBucketQuery(input.bucket, input.language);
    const page = await this.searchInternal({
      query,
      language: input.language,
      limit: input.limit,
      pageToken: input.cursor,
      bucket: input.bucket,
    });
    return {...page, query};
  }

  async search(input: {
    query: string;
    language: string;
    limit: number;
    cursor?: string | null;
  }): Promise<HumorSourcePage> {
    // Allowlisted callers only — orchestrator never forwards raw client strings.
    const page = await this.searchInternal({
      query: input.query,
      language: input.language,
      limit: input.limit,
      pageToken: input.cursor,
      bucket: "meme",
    });
    return {
      items: page.normalized
        .map(normalizedToSourceItem)
        .filter((i): i is HumorSourceItem => i != null),
      nextCursor: page.nextCursor,
    };
  }

  async getVideos(input: {
    language: string;
    limit: number;
    cursor?: string | null;
    query?: string;
  }): Promise<HumorSourcePage> {
    return this.search({
      query: input.query ?? pickBucketQuery("turkish", input.language),
      language: input.language,
      limit: input.limit,
      cursor: input.cursor,
    });
  }

  async getImages(): Promise<HumorSourcePage> {
    return {items: [], nextCursor: null};
  }

  async getNextPage(cursor: string): Promise<HumorSourcePage> {
    return this.getVideos({language: "tr", limit: 10, cursor});
  }
}
