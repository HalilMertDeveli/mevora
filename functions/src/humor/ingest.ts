import type {Firestore} from "firebase-admin/firestore";
import {applyHumorAiTagging} from "./aiTagging.js";
import {isHumorCategory, type HumorCategory} from "./categories.js";
import {
  upsertHumorContentDoc,
  type UpsertHumorContentInput,
} from "./contentRepository.js";
import {
  probeMediaUrl,
  validateHumorSourceItem,
} from "./contentValidation.js";
import {GiphyHumorSource, GIPHY_TR_QUERIES} from "./giphySource.js";
import {GIPHY_ACTIVE, isGiphyConfigured} from "./humorApiConfig.js";
import type {HumorSourceItem} from "./sourceAdapter.js";

function contentIdFor(provider: string, sourceId: string): string {
  return `ext_${provider}_${sourceId}`.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 120);
}

function guessCategory(item: HumorSourceItem): HumorCategory {
  const blob = `${item.title ?? ""} ${(item.tags ?? []).join(" ")}`.toLowerCase();
  if (blob.includes("sarcas") || blob.includes("iron")) return "sarcasm";
  if (blob.includes("absur") || blob.includes("absürt")) return "absurd";
  if (blob.includes("roman") || blob.includes("aşk") || blob.includes("love")) {
    return "romantic";
  }
  if (blob.includes("dark") || blob.includes("karan")) return "dark";
  if (blob.includes("cringe")) return "cringe";
  if (blob.includes("teas") || blob.includes("takıl")) return "teasing";
  if (blob.includes("word") || blob.includes("kelime") || blob.includes("pun")) {
    return "wordplay";
  }
  if (blob.includes("dry") || blob.includes("kuruh")) return "dry";
  if (blob.includes("meme")) return "meme";
  if (blob.includes("silly") || blob.includes("saçma") || blob.includes("komik")) {
    return "silly";
  }
  return "meme";
}

export async function ingestHumorSourceItem(
  db: Firestore,
  item: HumorSourceItem,
  provider: string,
  options?: {
    probe?: boolean;
    forcedCategory?: string;
    attributionRequired?: boolean;
    embedUrl?: string | null;
  },
): Promise<{upserted: boolean; contentId: string; reason?: string}> {
  const validation = validateHumorSourceItem(item);
  if (!validation.ok) {
    return {upserted: false, contentId: "", reason: validation.reason};
  }

  if (options?.probe !== false) {
    const probeUrl =
      item.media.downloadUrl.includes("youtube.com/embed") ||
      item.media.downloadUrl.includes("youtu.be")
        ? item.media.thumbUrl || item.media.previewUrl
        : item.media.downloadUrl;
    if (probeUrl) {
      const ok = await probeMediaUrl(probeUrl);
      if (!ok) {
        return {upserted: false, contentId: "", reason: "media-unreachable"};
      }
    }
  }

  const contentId = contentIdFor(provider, item.sourceId);
  const existing = await db.collection("humorContent").doc(contentId).get();
  if (existing.exists && existing.data()?.active === true) {
    return {upserted: false, contentId, reason: "duplicate"};
  }

  const categoryGuess =
    options?.forcedCategory && isHumorCategory(options.forcedCategory)
      ? options.forcedCategory
      : guessCategory(item);
  const tagged = applyHumorAiTagging({
    suggestedCategory: isHumorCategory(categoryGuess) ? categoryGuess : "meme",
    suggestedTags: [
      ...(item.tags ?? []),
      ...(item.title ? [item.title] : []),
    ],
    suggestedVector: {[categoryGuess]: 0.75, meme: 0.55},
    suggestedSafetyFlags: {},
  });

  const embedUrl = options?.embedUrl ?? item.media.embedUrl ?? null;
  const attributionRequired =
    options?.attributionRequired === true ||
    item.media.attributionRequired === true ||
    provider === "giphy" ||
    provider === "youtube";

  const isYoutube =
    provider === "youtube" || Boolean(embedUrl?.includes("youtube.com/embed"));
  const rawDownload = item.media.downloadUrl ?? "";
  const isYoutubeEmbedDownload =
    rawDownload.includes("youtube.com/embed") ||
    rawDownload.includes("youtu.be/");

  // Never copy third-party bytes into Firebase Storage — CDN/embed URLs only.
  // YouTube: keep poster/thumb in downloadUrl (or null); play only via embedUrl + iframe.
  const input: UpsertHumorContentInput = {
    contentId,
    type: item.type === "video" ? "video" : item.type === "image" ? "image" : "meme",
    language: item.language || "tr",
    category: tagged.category,
    humorTags: tagged.humorTags.length ? tagged.humorTags : item.tags,
    humorVector: tagged.humorVector,
    media: {
      downloadUrl:
        isYoutube || isYoutubeEmbedDownload
          ? item.media.thumbUrl ?? item.media.previewUrl ?? null
          : rawDownload || null,
      thumbUrl: item.media.thumbUrl ?? item.media.previewUrl ?? null,
      durationMs: item.media.durationMs ?? null,
      aspectRatio: item.media.aspectRatio ?? null,
      textBody: item.media.textBody ?? item.title ?? null,
      embedUrl,
      attributionRequired,
    },
    safetyFlags: tagged.safetyFlags,
    safetyStatus: tagged.safetyStatus === "approved" ? "approved" : tagged.safetyStatus,
    active: tagged.safetyStatus === "approved",
    sourceType: "licensed_api",
    provider,
    licenseRef: item.sourceUrl ?? null,
  };

  const doc = await upsertHumorContentDoc(db, input);
  await db.collection("humorContent").doc(doc.contentId).set(
    {
      sourceId: item.sourceId,
      sourceUrl: item.sourceUrl ?? null,
      thumbnailUrl: item.media.thumbUrl ?? null,
      duration: item.media.durationMs ?? null,
      "media.embedUrl": embedUrl,
      "media.attributionRequired": attributionRequired,
    },
    {merge: true},
  );

  return {upserted: true, contentId: doc.contentId};
}

export async function syncHumorFromGiphy(input: {
  db: Firestore;
  language?: string;
  limit?: number;
  probe?: boolean;
}): Promise<{
  configured: boolean;
  fetched: number;
  upserted: number;
  skipped: number;
  reasons: Record<string, number>;
}> {
  if (!GIPHY_ACTIVE) {
    return {
      configured: false,
      fetched: 0,
      upserted: 0,
      skipped: 0,
      reasons: {giphy_disabled: 1},
    };
  }
  if (!isGiphyConfigured()) {
    return {
      configured: false,
      fetched: 0,
      upserted: 0,
      skipped: 0,
      reasons: {not_configured: 1},
    };
  }
  const source = GiphyHumorSource.tryCreate();
  if (!source) {
    return {
      configured: false,
      fetched: 0,
      upserted: 0,
      skipped: 0,
      reasons: {not_configured: 1},
    };
  }

  const language = (input.language ?? "tr").toLowerCase().startsWith("tr")
    ? "tr"
    : "en";
  const limit = Math.min(40, Math.max(8, input.limit ?? 24));
  const queries = language === "tr" ? GIPHY_TR_QUERIES : ["funny", "meme", "lol"];
  const reasons: Record<string, number> = {};
  let fetched = 0;
  let upserted = 0;
  let skipped = 0;

  for (const query of queries.slice(0, 4)) {
    const page = await source.search({
      query,
      language,
      limit: Math.ceil(limit / 4),
    });
    fetched += page.items.length;
    for (const item of page.items) {
      const result = await ingestHumorSourceItem(input.db, item, "giphy", {
        probe: input.probe ?? true,
      });
      if (result.upserted) {
        upserted += 1;
      } else {
        skipped += 1;
        const key = result.reason ?? "skipped";
        reasons[key] = (reasons[key] ?? 0) + 1;
      }
    }
  }

  return {configured: true, fetched, upserted, skipped, reasons};
}
