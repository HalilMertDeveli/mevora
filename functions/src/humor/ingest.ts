import {FieldValue, type DocumentData, type Firestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {safeLogMeta} from "../security/logHygiene.js";
import {applyHumorAiTagging} from "./aiTagging.js";
import type {HumorCategory, HumorVector} from "./categories.js";
import {
  upsertHumorContentDoc,
  type UpsertHumorContentInput,
} from "./contentRepository.js";
import {
  isAllowedMediaUrl,
  probeMediaUrl,
  validateHumorSourceItem,
} from "./contentValidation.js";
import {
  cleanProviderTitle,
  GiphyHumorSource,
  mediaPathKey,
  selectQueryFamilies,
  titleIdentityKey,
} from "./giphySource.js";
import {isGiphyConfigured} from "./humorApiConfig.js";
import {
  assessProviderRelevance,
  foldedWords,
  providerSourceTrust,
} from "./providerRelevance.js";
import type {HumorSourceItem} from "./sourceAdapter.js";
import type {HumorAttribution} from "./types.js";

export function contentIdFor(provider: string, sourceId: string): string {
  return `ext_${provider}_${sourceId}`.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 120);
}

/** Keyword stems → category. First match wins; order is most specific first. */
const KEYWORD_CATEGORIES: ReadonlyArray<[HumorCategory, readonly string[]]> = [
  ["sarcasm", ["sarcas", "sarkas", "irony", "ironic", "ironi", "eyeroll"]],
  ["absurd", ["absur", "absurt", "surreal"]],
  ["romantic", ["roman", "love", "flirt", "ask"]],
  ["dark", ["dark", "karanlik", "karamizah"]],
  ["cringe", ["cring", "awkward", "utanc", "rezil"]],
  ["teasing", ["teas", "takil", "roast"]],
  ["wordplay", ["pun", "wordplay", "kelime"]],
  ["dry", ["deadpan", "dry", "kuru"]],
  ["meme", ["meme"]],
  ["silly", ["silly", "goofy", "sacma", "komik", "funny"]],
];

/**
 * Keyword guess from the provider's own text, or null when nothing matched.
 * Whole-word (or, for stems of 5+ letters, word-prefix) matching on folded
 * text, so "ironman" is not irony and "pundit" is not a pun.
 */
export function keywordCategory(item: HumorSourceItem): HumorCategory | null {
  const words = foldedWords(
    [item.title, item.rawTitle, item.slug, item.altText, ...(item.tags ?? [])]
      .filter(Boolean)
      .join(" "),
  );
  for (const [category, stems] of KEYWORD_CATEGORIES) {
    const hit = words.some((word) =>
      stems.some((stem) => word === stem || (stem.length >= 5 && word.startsWith(stem))),
    );
    if (hit) {
      return category;
    }
  }
  return null;
}

/**
 * Query-aware category inference.
 *
 * The query family's category is the primary signal: an item returned for
 * "sarcastic reaction" is most likely sarcastic. A keyword in the item's own
 * text adds a secondary dimension. Weights stay modest (at most 0.6) on
 * purpose: this is a search-context guess, not a measurement, and the vector
 * must not pretend otherwise. User ratings move the profile, not this guess.
 */
export function inferProviderCategory(item: HumorSourceItem): {
  category: HumorCategory;
  vector: Partial<HumorVector>;
} {
  const keyword = keywordCategory(item);
  const primary = item.queryCategory ?? keyword ?? "meme";
  const vector: Partial<HumorVector> = {
    [primary]: item.queryCategory ? 0.6 : keyword ? 0.5 : 0.4,
  };
  if (keyword && keyword !== primary) {
    vector[keyword] = 0.35;
  }
  return {category: primary, vector};
}

/**
 * True when `data` is a GIPHY GIF that an earlier ingest stored as MP4 video
 * and `item` — the provider result for that same sourceId, fetched again — now
 * maps to an animated image. Every condition must hold:
 * - the doc is `ext_giphy_*`, a licensed GIPHY item, still approved AND active
 *   (rejected / pending / deactivated docs are never touched, so moderation
 *   can never be undone from here);
 * - it is stored as `type: "video"` with no duration (GIF ingest never wrote
 *   one; a Clip carries its real duration);
 * - its stored MP4 is one of this GIF's own MP4 renditions (same `<id>/<file>`
 *   tail), which a Clip's assets never are;
 * - the fresh item is a GIF (not a Clip) whose new media is an allowed image.
 */
export function isLegacyGifVideoDoc(
  contentId: string,
  data: DocumentData | undefined,
  item: HumorSourceItem,
): boolean {
  if (!data || !contentId.startsWith("ext_giphy_")) return false;
  if (item.origin !== "gif" || item.type === "video" || item.type === "text") return false;
  if (!isAllowedMediaUrl(item.media?.downloadUrl)) return false;
  if (data.source?.type !== "licensed_api" || data.source?.provider !== "giphy") return false;
  if (data.safetyStatus !== "approved" || data.active !== true) return false;
  if (data.type !== "video") return false;
  const media = (data.media ?? {}) as Record<string, unknown>;
  if (media.durationMs !== null && media.durationMs !== undefined) return false;
  const storedKey = mediaPathKey(typeof media.downloadUrl === "string" ? media.downloadUrl : null);
  if (!storedKey || !storedKey.endsWith(".mp4")) return false;
  return (item.legacyVideoKeys ?? []).includes(storedKey);
}

/**
 * Narrow, idempotent migration used only by the provider sync: swaps a legacy
 * GIF-as-MP4 doc's `type` and `media.downloadUrl` / `media.aspectRatio` to the
 * animated-image rendition. Re-checked inside a transaction, so a doc an admin
 * rejects or deactivates meanwhile is left alone; never touches safety status,
 * `active`, the poster, the caption, attribution, trust or calibration.
 * Returns true only when it wrote.
 */
export async function migrateLegacyGifVideoDoc(
  db: Firestore,
  contentId: string,
  item: HumorSourceItem,
  options?: {probe?: boolean},
): Promise<boolean> {
  if (options?.probe !== false && !(await probeMediaUrl(item.media.downloadUrl))) {
    return false;
  }
  const ref = db.collection("humorContent").doc(contentId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() : undefined;
    if (!isLegacyGifVideoDoc(contentId, data, item)) {
      return false;
    }
    const aspectRatio = item.media.aspectRatio ?? data?.media?.aspectRatio ?? null;
    tx.update(ref, {
      "type": "meme",
      "media.downloadUrl": item.media.downloadUrl,
      "media.aspectRatio": aspectRatio,
      "updatedAt": FieldValue.serverTimestamp(),
    });
    return true;
  });
}

export async function ingestHumorSourceItem(
  db: Firestore,
  item: HumorSourceItem,
  provider: string,
  options?: {probe?: boolean},
): Promise<{upserted: boolean; contentId: string; reason?: string}> {
  const validation = validateHumorSourceItem(item);
  if (!validation.ok) {
    return {upserted: false, contentId: "", reason: validation.reason};
  }

  // An item already in the catalog is never rewritten by a provider sync. The
  // upsert below would classify it afresh (provider items carry no safety
  // flags, so always 'approved') and set active=true, silently undoing an
  // admin's rejection or deactivation every time an admin refreshed the feed.
  const contentId = contentIdFor(provider, item.sourceId);
  const existing = await db.collection("humorContent").doc(contentId).get();
  if (existing.exists) {
    // The one exception: a GIF stored as MP4 video before GIFs became
    // animated images gets its rendition (type + media) swapped — nothing else.
    if (
      provider === "giphy" &&
      isLegacyGifVideoDoc(contentId, existing.data(), item) &&
      (await migrateLegacyGifVideoDoc(db, contentId, item, options))
    ) {
      return {upserted: false, contentId, reason: "migrated"};
    }
    return {
      upserted: false,
      contentId,
      reason: existing.data()?.safetyStatus === "rejected" ? "rejected" : "duplicate",
    };
  }

  if (options?.probe !== false) {
    const ok = await probeMediaUrl(item.media.downloadUrl);
    if (!ok) {
      return {upserted: false, contentId: "", reason: "media-unreachable"};
    }
  }

  const attribution: HumorAttribution = item.attribution ?? {
    provider,
    displayName: null,
    username: null,
    sourceUrl: item.sourceUrl ?? null,
    verified: false,
  };
  const inferred = inferProviderCategory(item);
  const tagged = applyHumorAiTagging({
    suggestedCategory: inferred.category,
    suggestedTags: item.tags ?? [],
    suggestedVector: inferred.vector,
    suggestedSafetyFlags: {},
  });

  const input: UpsertHumorContentInput = {
    contentId,
    type: item.type === "video" ? "video" : item.type === "image" ? "image" : "meme",
    language: item.language || "tr",
    category: tagged.category,
    humorTags: tagged.humorTags,
    humorVector: tagged.humorVector,
    media: {
      downloadUrl: item.media.downloadUrl,
      thumbUrl: item.media.thumbUrl ?? null,
      durationMs: item.media.durationMs ?? null,
      aspectRatio: item.media.aspectRatio ?? null,
      // The provider's own title for this item, cleaned; never our text.
      textBody:
        item.media.textBody !== undefined
          ? item.media.textBody
          : cleanProviderTitle(item.title ?? null, attribution),
    },
    safetyFlags: tagged.safetyFlags,
    safetyStatus: tagged.safetyStatus === "approved" ? "approved" : tagged.safetyStatus,
    active: tagged.safetyStatus === "approved",
    sourceType: "licensed_api",
    provider,
    licenseRef: item.sourceUrl ?? null,
    // Provider content never becomes calibration content, whatever it claims.
    calibration: {eligible: false},
    sourceTrust: providerSourceTrust(attribution),
    attribution,
    sourceId: item.sourceId,
    sourceUrl: item.sourceUrl ?? null,
  };

  const doc = await upsertHumorContentDoc(db, input);
  return {upserted: true, contentId: doc.contentId};
}

export type HumorProviderSyncResult = {
  configured: boolean;
  language: "tr" | "en";
  /** Queries used, in order. */
  queries: string[];
  /** Items asked of the provider (sum of per-request limits). */
  requested: number;
  /** Provider objects actually received. */
  fetched: number;
  /** New catalogue documents written. */
  accepted: number;
  /** Rejected items by reason (mapping, relevance, validation, probe). */
  rejected: Record<string, number>;
  /** Within-batch repeats plus items already in the catalogue. */
  duplicates: number;
  /** Legacy GIF-as-MP4 docs switched to their animated-image rendition. */
  migrated: number;
  /** Provider request failures by kind (status only; never a URL). */
  errors: Record<string, number>;
  /** True only when the Clips endpoint answered for this key. */
  clipsAvailable: boolean;
};

type SyncSource = Pick<GiphyHumorSource, "searchGifs" | "searchClips">;

function bump(map: Record<string, number>, key: string, by = 1): void {
  if (by > 0) {
    map[key] = (map[key] ?? 0) + by;
  }
}

/** UTC day number: the default deterministic rotation for a sync. */
export function dayRotation(now = Date.now()): number {
  return Math.floor(now / 86_400_000);
}

/**
 * Pull licensed GIPHY content into `humorContent`.
 *
 * map (own media, poster, title, attribution) -> relevance filter -> within-
 * batch dedup -> validate / existing-doc check / optional reachability probe
 * -> write. Returns fewer items rather than filler: the limit is a ceiling,
 * not a target. Logs one summary line: counts only, never the key or a URL.
 */
export async function syncHumorFromGiphy(input: {
  db: Firestore;
  language?: string;
  limit?: number;
  probe?: boolean;
  /** Injected for tests; otherwise built from GIPHY_API_KEY. */
  source?: SyncSource | null;
  clipsEnabled?: boolean;
  /** Query rotation; defaults to the UTC day number. */
  rotation?: number;
  queryCount?: number;
  log?: (message: string, meta: Record<string, unknown>) => void;
}): Promise<HumorProviderSyncResult> {
  const language = (input.language ?? "tr").toLowerCase().startsWith("tr") ? "tr" : "en";
  const result: HumorProviderSyncResult = {
    configured: false,
    language,
    queries: [],
    requested: 0,
    fetched: 0,
    accepted: 0,
    rejected: {},
    duplicates: 0,
    migrated: 0,
    errors: {},
    clipsAvailable: false,
  };

  const source =
    input.source ??
    (isGiphyConfigured() ? GiphyHumorSource.tryCreate({clipsEnabled: input.clipsEnabled}) : null);
  if (!source) {
    return result;
  }
  result.configured = true;

  const limit = Math.min(40, Math.max(8, Math.floor(input.limit ?? 24)));
  const rotation = input.rotation ?? dayRotation();
  const families = selectQueryFamilies(language, Math.max(1, input.queryCount ?? 4), rotation);
  const perQuery = Math.ceil(limit / Math.max(1, families.length));
  // Deterministic paging: every full pass over the families moves one page
  // deeper, so repeated syncs do not re-read the same first results forever.
  const offset = (Math.floor(rotation / Math.max(1, families.length)) % 5) * perQuery;
  let clipsDenied = false;

  const seenSourceIds = new Set<string>();
  const seenMedia = new Set<string>();
  const seenTitles = new Set<string>();

  for (const family of families) {
    if (result.accepted >= limit) {
      break;
    }
    result.queries.push(family.query);
    const candidates: HumorSourceItem[] = [];

    if (!clipsDenied) {
      try {
        const clips = await source.searchClips({
          query: family.query,
          language: family.language,
          limit: perQuery,
          offset,
          family,
        });
        if (clips.available) {
          result.clipsAvailable = true;
          result.requested += perQuery;
          result.fetched += clips.received;
          for (const [reason, n] of Object.entries(clips.rejected)) bump(result.rejected, reason, n);
          candidates.push(...clips.items);
        } else {
          // Disabled, or no Clips access for this key: GIF search only from now on.
          clipsDenied = true;
        }
      } catch (error) {
        bump(result.errors, error instanceof Error ? error.message : "giphy-clips-error");
      }
    }

    try {
      const gifs = await source.searchGifs({
        query: family.query,
        language: family.language,
        limit: perQuery,
        offset,
        family,
      });
      result.requested += perQuery;
      result.fetched += gifs.received;
      for (const [reason, n] of Object.entries(gifs.rejected)) bump(result.rejected, reason, n);
      candidates.push(...gifs.items);
    } catch (error) {
      bump(result.errors, error instanceof Error ? error.message : "giphy-error");
    }

    for (const item of candidates) {
      if (result.accepted >= limit) {
        break;
      }
      const verdict = assessProviderRelevance(item);
      if (!verdict.ok) {
        bump(result.rejected, verdict.reason);
        continue;
      }
      const titleKey = titleIdentityKey(item);
      if (
        seenSourceIds.has(item.sourceId) ||
        seenMedia.has(item.media.downloadUrl) ||
        (titleKey !== null && seenTitles.has(titleKey))
      ) {
        result.duplicates += 1;
        continue;
      }
      seenSourceIds.add(item.sourceId);
      seenMedia.add(item.media.downloadUrl);
      if (titleKey !== null) seenTitles.add(titleKey);

      const written = await ingestHumorSourceItem(input.db, item, "giphy", {
        probe: input.probe ?? true,
      });
      if (written.upserted) {
        result.accepted += 1;
      } else if (written.reason === "migrated") {
        result.migrated += 1;
      } else if (written.reason === "duplicate") {
        result.duplicates += 1;
      } else {
        bump(
          result.rejected,
          written.reason === "rejected" ? "previously-rejected" : written.reason ?? "skipped",
        );
      }
    }
  }

  const log = input.log ?? ((message, meta) => logger.info(message, meta));
  log(
    "humor provider sync",
    safeLogMeta({
      provider: "giphy",
      language: result.language,
      queries: result.queries.length,
      requested: result.requested,
      fetched: result.fetched,
      accepted: result.accepted,
      duplicates: result.duplicates,
      migrated: result.migrated,
      rejected: result.rejected,
      errors: result.errors,
      clipsAvailable: result.clipsAvailable,
    }),
  );
  return result;
}
