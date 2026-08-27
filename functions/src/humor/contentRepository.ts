import {FieldValue, type DocumentData, type Firestore} from "firebase-admin/firestore";
import {
  isHumorCategory,
  normalizeHumorVector,
  type HumorCategory,
  type HumorVector,
} from "./categories.js";
import {classifyHumorSafety, emptySafetyFlags} from "./moderation.js";
import {resolveHumorSourceAdapter} from "./sourceAdapter.js";
import type {
  HumorContentDoc,
  HumorContentType,
  HumorFeedItem,
  HumorMedia,
  HumorSafetyFlags,
  HumorSafetyStatus,
} from "./types.js";

export const HUMOR_CONTENT_COLLECTION = "humorContent";

export function toFeedSafeContent(doc: HumorContentDoc): HumorFeedItem {
  const media = doc.media ?? {};
  const provider = doc.source?.provider ?? null;
  const sourceId = extractProviderSourceId(doc.contentId, provider);
  return {
    contentId: doc.contentId,
    type: doc.type,
    language: doc.language,
    category: doc.category,
    humorTags: doc.humorTags,
    media: {
      downloadUrl: media.downloadUrl ?? null,
      thumbUrl: media.thumbUrl ?? null,
      durationMs: media.durationMs ?? null,
      aspectRatio: media.aspectRatio ?? null,
      textBody: media.textBody ?? null,
      embedUrl: media.embedUrl ?? null,
      attributionRequired: media.attributionRequired === true,
    },
    provider,
    sourceId,
    attributionRequired:
      media.attributionRequired === true ||
      provider === "giphy" ||
      provider === "youtube",
    sourceUrl: doc.source?.licenseRef ?? null,
  };
}

/** Prefer `ext_<provider>_<sourceId>` content ids written by ingest. */
export function extractProviderSourceId(
  contentId: string,
  provider: string | null | undefined,
): string | null {
  if (!provider || provider === "mevora-internal") {
    return null;
  }
  const prefix = `ext_${provider}_`;
  if (contentId.startsWith(prefix) && contentId.length > prefix.length) {
    return contentId.slice(prefix.length);
  }
  return null;
}

export function parseHumorContent(
  contentId: string,
  data: DocumentData | undefined,
): HumorContentDoc | null {
  if (!data) {
    return null;
  }
  const categoryRaw = String(data.category ?? "");
  if (!isHumorCategory(categoryRaw)) {
    return null;
  }
  const type = String(data.type ?? "text");
  const safetyStatus = String(data.safetyStatus ?? "pending") as HumorSafetyStatus;
  return {
    contentId,
    type: (["image", "video", "text", "meme"].includes(type)
      ? type
      : "text") as HumorContentType,
    language: String(data.language ?? "en").toLowerCase(),
    category: categoryRaw,
    humorTags: Array.isArray(data.humorTags)
      ? data.humorTags.map((t: unknown) => String(t))
      : [],
    humorVector: normalizeHumorVector(data.humorVector ?? {}, 0),
    media: (data.media ?? {}) as HumorMedia,
    safetyStatus,
    safetyFlags: emptySafetyFlags(data.safetyFlags ?? {}),
    source: {
      type: data.source?.type === "licensed_api" ? "licensed_api" : "internal",
      provider: data.source?.provider ?? "mevora-internal",
      licenseRef: data.source?.licenseRef ?? null,
    },
    createdAt: data.createdAt,
    updatedAt: data.updatedAt,
    active: data.active === true,
    stats: {
      viewCount: Number(data.stats?.viewCount ?? 0),
      ratingCount: Number(data.stats?.ratingCount ?? 0),
      avgRating: Number(data.stats?.avgRating ?? 0),
    },
  };
}

export async function loadHumorContent(
  db: Firestore,
  contentId: string,
): Promise<HumorContentDoc | null> {
  const snap = await db.collection(HUMOR_CONTENT_COLLECTION).doc(contentId).get();
  if (!snap.exists) {
    return null;
  }
  return parseHumorContent(snap.id, snap.data());
}

export async function listCandidateHumorContent(
  db: Firestore,
  input: {languages: string[]; limit: number},
): Promise<HumorContentDoc[]> {
  const languages = input.languages.map((l) => l.toLowerCase()).filter(Boolean);
  const limit = Math.min(200, Math.max(input.limit, 40));
  // Prefer indexed query; fall back to broader scan if composite index missing.
  try {
    let query = db
      .collection(HUMOR_CONTENT_COLLECTION)
      .where("active", "==", true)
      .where("safetyStatus", "==", "approved")
      .limit(limit);
    if (languages.length === 1) {
      query = query.where("language", "==", languages[0]);
    }
    const snap = await query.get();
    const items = snap.docs
      .map((doc) => parseHumorContent(doc.id, doc.data()))
      .filter((item): item is HumorContentDoc => item != null);
    if (languages.length > 1) {
      return items.filter((item) => languages.includes(item.language));
    }
    return items;
  } catch {
    const snap = await db
      .collection(HUMOR_CONTENT_COLLECTION)
      .where("active", "==", true)
      .limit(limit)
      .get();
    return snap.docs
      .map((doc) => parseHumorContent(doc.id, doc.data()))
      .filter((item): item is HumorContentDoc => {
        if (!item) return false;
        if (item.safetyStatus !== "approved") return false;
        if (languages.length && !languages.includes(item.language)) return false;
        return true;
      });
  }
}

export type UpsertHumorContentInput = {
  contentId: string;
  type: HumorContentType;
  language: string;
  category: HumorCategory;
  humorTags?: string[];
  humorVector: HumorVector | Partial<HumorVector>;
  media?: HumorMedia;
  safetyFlags?: Partial<HumorSafetyFlags>;
  safetyStatus?: HumorSafetyStatus;
  active?: boolean;
  sourceType?: "internal" | "licensed_api";
  provider?: string;
  licenseRef?: string | null;
};

export async function upsertHumorContentDoc(
  db: Firestore,
  input: UpsertHumorContentInput,
): Promise<HumorContentDoc> {
  const adapter = resolveHumorSourceAdapter(
    input.sourceType ?? "internal",
    input.provider ?? "mevora-internal",
  );
  const classified = classifyHumorSafety(input.safetyFlags);
  const safetyStatus = input.safetyStatus ?? classified.status;
  const active = input.active === true && safetyStatus === "approved";
  const doc = {
    contentId: input.contentId,
    type: input.type,
    language: input.language.toLowerCase(),
    category: input.category,
    humorTags: (input.humorTags ?? []).map((t) => t.trim()).filter(Boolean),
    humorVector: normalizeHumorVector(input.humorVector, 0),
    media: input.media ?? {},
    safetyStatus,
    safetyFlags: classified.flags,
    source: {
      type: adapter.kind,
      provider: adapter.provider,
      licenseRef: input.licenseRef ?? null,
    },
    active,
    stats: {
      viewCount: 0,
      ratingCount: 0,
      avgRating: 0,
    },
  };
  const ref = db.collection(HUMOR_CONTENT_COLLECTION).doc(input.contentId);
  const existing = await ref.get();
  const payload = {
    ...doc,
    updatedAt: FieldValue.serverTimestamp(),
    ...(existing.exists ? {} : {createdAt: FieldValue.serverTimestamp()}),
    stats: existing.exists ? (existing.data()?.stats ?? doc.stats) : doc.stats,
  };
  await ref.set(payload, {merge: true});
  return parseHumorContent(input.contentId, {
    ...doc,
    stats: payload.stats,
  })!;
}

/** Internal seed — Turkish-first real playable media (no scraping).
 * Videos: Google sample bucket (public HTTPS MP4).
 * Images: picsum (public HTTPS). Captions are Mevora-authored Turkish humor.
 */
export const INTERNAL_HUMOR_SEED: Array<Omit<UpsertHumorContentInput, "safetyStatus">> = [
  {
    contentId: "hc_tr_vid_001",
    type: "video",
    language: "tr",
    category: "absurd",
    humorTags: ["absürt", "video"],
    humorVector: {absurd: 0.85, silly: 0.6, meme: 0.4},
    media: {
      downloadUrl:
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
      thumbUrl:
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerBlazes.jpg",
      durationMs: 15000,
      aspectRatio: 16 / 9,
      textBody: "Alarm değil, sabah sabotajı.",
    },
    active: true,
    sourceType: "internal",
    provider: "mevora-internal",
  },
  {
    contentId: "hc_tr_vid_002",
    type: "video",
    language: "tr",
    category: "situational",
    humorTags: ["günlük", "video"],
    humorVector: {situational: 0.88, dry: 0.45, silly: 0.5},
    media: {
      downloadUrl:
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4",
      thumbUrl:
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerEscapes.jpg",
      durationMs: 15000,
      aspectRatio: 16 / 9,
      textBody: "Buzdolabı yine boş fikirler sunuyor.",
    },
    active: true,
  },
  {
    contentId: "hc_tr_vid_003",
    type: "video",
    language: "tr",
    category: "silly",
    humorTags: ["saçma", "video"],
    humorVector: {silly: 0.9, absurd: 0.55, meme: 0.35},
    media: {
      downloadUrl:
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4",
      thumbUrl:
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerFun.jpg",
      durationMs: 60000,
      aspectRatio: 16 / 9,
      textBody: "Planım vardı… sonra pazartesi oldu.",
    },
    active: true,
  },
  {
    contentId: "hc_tr_vid_004",
    type: "video",
    language: "tr",
    category: "meme",
    humorTags: ["meme", "video"],
    humorVector: {meme: 0.9, situational: 0.6, cringe: 0.25},
    media: {
      downloadUrl:
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4",
      thumbUrl:
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerJoyrides.jpg",
      durationMs: 15000,
      aspectRatio: 16 / 9,
      textBody: "Wi‑Fi şifresi kadar karmaşık bir ruh hali.",
    },
    active: true,
  },
  {
    contentId: "hc_tr_img_001",
    type: "meme",
    language: "tr",
    category: "sarcasm",
    humorTags: ["ironi", "meme"],
    humorVector: {sarcasm: 0.88, dry: 0.55, teasing: 0.4},
    media: {
      downloadUrl: "https://picsum.photos/seed/mevora-tr-1/1080/1920",
      thumbUrl: "https://picsum.photos/seed/mevora-tr-1/540/960",
      aspectRatio: 9 / 16,
      textBody: "Tabii, trafik yine benim yüzümden oluştu.",
    },
    active: true,
  },
  {
    contentId: "hc_tr_img_002",
    type: "image",
    language: "tr",
    category: "wordplay",
    humorTags: ["kelime", "espri"],
    humorVector: {wordplay: 0.85, silly: 0.55},
    media: {
      downloadUrl: "https://picsum.photos/seed/mevora-tr-2/1080/1920",
      thumbUrl: "https://picsum.photos/seed/mevora-tr-2/540/960",
      aspectRatio: 9 / 16,
      textBody: "Kahve olmadan ben 'ben' değilim; 'be n'.",
    },
    active: true,
  },
  {
    contentId: "hc_tr_img_003",
    type: "meme",
    language: "tr",
    category: "teasing",
    humorTags: ["takılma"],
    humorVector: {teasing: 0.86, romantic: 0.35, silly: 0.45},
    media: {
      downloadUrl: "https://picsum.photos/seed/mevora-tr-3/1080/1920",
      thumbUrl: "https://picsum.photos/seed/mevora-tr-3/540/960",
      aspectRatio: 9 / 16,
      textBody: "Poker suratın tatilde galiba.",
    },
    active: true,
  },
  {
    contentId: "hc_tr_img_004",
    type: "image",
    language: "tr",
    category: "cringe",
    humorTags: ["cringe", "sosyal"],
    humorVector: {cringe: 0.82, situational: 0.65, silly: 0.4},
    media: {
      downloadUrl: "https://picsum.photos/seed/mevora-tr-4/1080/1920",
      thumbUrl: "https://picsum.photos/seed/mevora-tr-4/540/960",
      aspectRatio: 9 / 16,
      textBody: "Arkandaki kişiye el sallayanı sandım. Klasik.",
    },
    active: true,
  },
  {
    contentId: "hc_tr_img_005",
    type: "meme",
    language: "tr",
    category: "dark",
    humorTags: ["kuru", "bitki"],
    humorVector: {dark: 0.68, dry: 0.6, situational: 0.4},
    media: {
      downloadUrl: "https://picsum.photos/seed/mevora-tr-5/1080/1920",
      thumbUrl: "https://picsum.photos/seed/mevora-tr-5/540/960",
      aspectRatio: 9 / 16,
      textBody: "Bitkilerimle karşılıklı ihmal anlaşmamız var.",
    },
    active: true,
  },
  {
    contentId: "hc_tr_vid_005",
    type: "video",
    language: "tr",
    category: "romantic",
    humorTags: ["romantik", "espri"],
    humorVector: {romantic: 0.75, teasing: 0.5, silly: 0.4},
    media: {
      downloadUrl:
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4",
      thumbUrl:
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerMeltdowns.jpg",
      durationMs: 15000,
      aspectRatio: 16 / 9,
      textBody: "Sen Wi‑Fi misin? Bağlantı hissediyorum.",
    },
    active: true,
  },
  {
    contentId: "hc_en_vid_001",
    type: "video",
    language: "en",
    category: "silly",
    humorTags: ["silly", "fallback"],
    humorVector: {silly: 0.8, meme: 0.5},
    media: {
      downloadUrl:
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
      thumbUrl:
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg",
      durationMs: 60000,
      aspectRatio: 16 / 9,
      textBody: "English fallback clip for bilingual users.",
    },
    active: true,
  },
  {
    contentId: "hc_en_img_001",
    type: "image",
    language: "en",
    category: "meme",
    humorTags: ["meme", "fallback"],
    humorVector: {meme: 0.85, situational: 0.5},
    media: {
      downloadUrl: "https://picsum.photos/seed/mevora-en-1/1080/1920",
      thumbUrl: "https://picsum.photos/seed/mevora-en-1/540/960",
      aspectRatio: 9 / 16,
      textBody: "English fallback still — TR feed stays primary.",
    },
    active: true,
  },
];
