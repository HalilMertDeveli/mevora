import type {Firestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {
  type HumorSearchBucket,
  pickBalancedBuckets,
  pickBucketQuery,
} from "./categoryQueries.js";
import {GiphyHumorSource} from "./giphySource.js";
import {isGiphyConfigured, isYoutubeConfigured} from "./humorApiConfig.js";
import {ingestHumorSourceItem} from "./ingest.js";
import {
  contentIdFromProvider,
  type NormalizedHumorContent,
  type NormalizedHumorProvider,
} from "./normalizedContent.js";
import {readProviderCache, writeProviderCache} from "./providerCache.js";
import {safeLogMeta} from "../security/logHygiene.js";
import {TENOR_API_STATUS} from "./tenorSource.js";
import {
  normalizedToSourceItem,
  YoutubeHumorSource,
} from "./youtubeSource.js";
import type {HumorSourceItem} from "./sourceAdapter.js";
import {BUCKET_TO_CATEGORY} from "./categoryQueries.js";

export type ProviderFetchErrorCode =
  | "not_configured"
  | "timeout"
  | "rate_limit"
  | "invalid_api_key"
  | "provider_unavailable"
  | "empty_result"
  | "unsafe_filtered"
  | "tenor_disabled"
  | "unknown";

export type ProviderAttempt = {
  provider: NormalizedHumorProvider;
  ok: boolean;
  fetched: number;
  upserted: number;
  error?: ProviderFetchErrorCode;
  detail?: string;
};

function classifyError(message: string): ProviderFetchErrorCode {
  const m = message.toLowerCase();
  if (m.includes("abort") || m.includes("timeout")) return "timeout";
  if (m.includes("rate") || m.includes("429") || m.includes("quota")) {
    return "rate_limit";
  }
  if (m.includes("invalid") || m.includes("401") || m.includes("403") || m.includes("forbidden")) {
    return "invalid_api_key";
  }
  if (m.includes("tenor")) return "tenor_disabled";
  if (m.includes("empty")) return "empty_result";
  return "unknown";
}

function giphyItemToNormalized(
  item: HumorSourceItem,
  bucket: HumorSearchBucket,
): NormalizedHumorContent {
  const isGif =
    item.media.mimeHint === "image/gif" ||
    (item.media.downloadUrl ?? "").includes(".gif");
  return {
    id: contentIdFromProvider("giphy", item.sourceId),
    provider: "giphy",
    providerContentId: item.sourceId,
    type: isGif && !item.media.downloadUrl?.includes(".mp4") ? "gif" : "video",
    title: item.title ?? "GIPHY",
    thumbnailUrl: item.media.thumbUrl ?? item.media.previewUrl ?? null,
    contentUrl: item.media.downloadUrl,
    embedUrl: null,
    durationMs: item.media.durationMs ?? null,
    category: BUCKET_TO_CATEGORY[bucket],
    language: item.language,
    tags: [...(item.tags ?? []), bucket, "giphy"],
    sourceUrl: item.sourceUrl ?? null,
    attributionRequired: true,
    createdAt: new Date().toISOString(),
  };
}

async function fetchYoutubeNormalized(input: {
  db: Firestore;
  language: string;
  bucket: HumorSearchBucket;
  limit: number;
}): Promise<NormalizedHumorContent[]> {
  const query = pickBucketQuery(input.bucket, input.language);
  const cacheKey = `yt_${input.language}_${input.bucket}_${query}`;
  const cached = await readProviderCache(input.db, "youtube", cacheKey);
  if (cached && cached.length > 0) {
    return cached.slice(0, input.limit);
  }
  const source = YoutubeHumorSource.tryCreate();
  if (!source) {
    throw new Error("youtube-not_configured");
  }
  const page = await source.searchByBucket({
    bucket: input.bucket,
    language: input.language,
    limit: input.limit,
  });
  if (page.normalized.length === 0) {
    throw new Error("youtube-empty");
  }
  await writeProviderCache(input.db, "youtube", cacheKey, page.normalized);
  return page.normalized.slice(0, input.limit);
}

async function fetchGiphyNormalized(input: {
  db: Firestore;
  language: string;
  bucket: HumorSearchBucket;
  limit: number;
}): Promise<NormalizedHumorContent[]> {
  const query = pickBucketQuery(input.bucket, input.language);
  const cacheKey = `gp_${input.language}_${input.bucket}_${query}`;
  const cached = await readProviderCache(input.db, "giphy", cacheKey);
  if (cached && cached.length > 0) {
    return cached.slice(0, input.limit);
  }
  const source = GiphyHumorSource.tryCreate();
  if (!source) {
    throw new Error("giphy-not_configured");
  }
  const page = await source.search({
    query,
    language: input.language,
    limit: input.limit,
  });
  const normalized = page.items.map((item) => giphyItemToNormalized(item, input.bucket));
  if (normalized.length === 0) {
    throw new Error("giphy-empty");
  }
  await writeProviderCache(input.db, "giphy", cacheKey, normalized);
  return normalized.slice(0, input.limit);
}

/**
 * Fallback chain (Terms-safe, free-tier oriented):
 * YouTube Data API → GIPHY → (Tenor disabled) → caller uses internal Firestore pool.
 *
 * Never downloads provider media into Firebase Storage.
 */
export async function topUpHumorFromProviders(input: {
  db: Firestore;
  languages: string[];
  needed: number;
  excludeIds: Set<string>;
  probe?: boolean;
}): Promise<{
  contentIds: string[];
  attempts: ProviderAttempt[];
  providersActive: NormalizedHumorProvider[];
}> {
  const needed = Math.max(0, Math.min(20, input.needed));
  const language = input.languages.find((l) => l.startsWith("tr")) ?? input.languages[0] ?? "tr";
  const buckets = pickBalancedBuckets(Math.max(3, Math.ceil(needed / 2)));
  const attempts: ProviderAttempt[] = [];
  const contentIds: string[] = [];
  const providersActive: NormalizedHumorProvider[] = [];

  if (!TENOR_API_STATUS.active) {
    attempts.push({
      provider: "tenor",
      ok: false,
      fetched: 0,
      upserted: 0,
      error: "tenor_disabled",
      detail: TENOR_API_STATUS.reason,
    });
  }

  const chain: Array<{
    provider: NormalizedHumorProvider;
    enabled: boolean;
    fetch: (bucket: HumorSearchBucket, limit: number) => Promise<NormalizedHumorContent[]>;
  }> = [
    {
      provider: "youtube",
      enabled: isYoutubeConfigured(),
      fetch: (bucket, limit) =>
        fetchYoutubeNormalized({db: input.db, language, bucket, limit}),
    },
    {
      provider: "giphy",
      enabled: isGiphyConfigured(),
      fetch: (bucket, limit) =>
        fetchGiphyNormalized({db: input.db, language, bucket, limit}),
    },
  ];

  for (const step of chain) {
    if (contentIds.length >= needed) {
      break;
    }
    if (!step.enabled) {
      attempts.push({
        provider: step.provider,
        ok: false,
        fetched: 0,
        upserted: 0,
        error: "not_configured",
      });
      continue;
    }

    let fetched = 0;
    let upserted = 0;
    let error: ProviderFetchErrorCode | undefined;
    let detail: string | undefined;

    try {
      for (const bucket of buckets) {
        if (contentIds.length >= needed) {
          break;
        }
        const remaining = needed - contentIds.length;
        const batch = await step.fetch(bucket, Math.max(3, remaining));
        fetched += batch.length;

        // Prefer playable stream URLs for in-app players; YouTube is embed-only.
        const ordered =
          step.provider === "giphy"
            ? batch
            : batch.filter((n) => n.embedUrl || n.contentUrl);

        for (const normalized of ordered) {
          if (contentIds.length >= needed) {
            break;
          }
          if (input.excludeIds.has(normalized.id)) {
            continue;
          }
          const sourceItem = normalizedToSourceItem(normalized);
          if (!sourceItem) {
            continue;
          }
          // Attach embed / attribution onto media for ingest merge fields.
          sourceItem.media.embedUrl = normalized.embedUrl;
          sourceItem.media.attributionRequired = normalized.attributionRequired;
          sourceItem.tags = [
            ...(sourceItem.tags ?? []),
            `category:${normalized.category}`,
            `bucket`,
          ];

          const result = await ingestHumorSourceItem(
            input.db,
            sourceItem,
            step.provider,
            {
              // Skip probe for YouTube embeds (HEAD often blocked); probe Giphy CDN.
              probe:
                input.probe ??
                (step.provider === "giphy"),
              forcedCategory: normalized.category,
              attributionRequired: normalized.attributionRequired,
              embedUrl: normalized.embedUrl,
            },
          );
          if (result.upserted || result.reason === "duplicate") {
            if (!input.excludeIds.has(result.contentId) && result.contentId) {
              contentIds.push(result.contentId);
              input.excludeIds.add(result.contentId);
              if (result.upserted) {
                upserted += 1;
              }
            }
          }
        }
      }

      if (fetched === 0) {
        error = "empty_result";
      }
      attempts.push({
        provider: step.provider,
        ok: fetched > 0,
        fetched,
        upserted,
        error,
      });
      if (fetched > 0) {
        providersActive.push(step.provider);
      }
    } catch (err) {
      const message = String(err);
      error = classifyError(message);
      detail = message.slice(0, 180);
      attempts.push({
        provider: step.provider,
        ok: false,
        fetched,
        upserted,
        error,
        detail,
      });
      logger.warn(
        "humor provider attempt failed",
        safeLogMeta({provider: step.provider, error: detail}),
      );
    }
  }

  providersActive.push("mevora-internal");
  return {contentIds, attempts, providersActive};
}
