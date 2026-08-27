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
  return {
    contentId: doc.contentId,
    type: doc.type,
    language: doc.language,
    category: doc.category,
    humorTags: doc.humorTags,
    media: {
      downloadUrl: doc.media?.downloadUrl ?? null,
      thumbUrl: doc.media?.thumbUrl ?? null,
      durationMs: doc.media?.durationMs ?? null,
      aspectRatio: doc.media?.aspectRatio ?? null,
      textBody: doc.media?.textBody ?? null,
    },
  };
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

/** Internal MVP seed — no third-party scraping. Text/meme only. */
export const INTERNAL_HUMOR_SEED: Array<Omit<UpsertHumorContentInput, "safetyStatus">> = [
  {
    contentId: "hc_seed_001",
    type: "text",
    language: "en",
    category: "wordplay",
    humorTags: ["pun", "office"],
    humorVector: {wordplay: 0.9, dry: 0.4, situational: 0.3},
    media: {textBody: "I told my computer I needed a break… it froze."},
    active: true,
  },
  {
    contentId: "hc_seed_002",
    type: "text",
    language: "en",
    category: "sarcasm",
    humorTags: ["sarcasm", "monday"],
    humorVector: {sarcasm: 0.85, dry: 0.55, situational: 0.4},
    media: {textBody: "Oh great, another meeting that could've been an email."},
    active: true,
  },
  {
    contentId: "hc_seed_003",
    type: "text",
    language: "en",
    category: "absurd",
    humorTags: ["absurd", "animals"],
    humorVector: {absurd: 0.9, silly: 0.7, meme: 0.3},
    media: {textBody: "A goose just billed me for emotional damages."},
    active: true,
  },
  {
    contentId: "hc_seed_004",
    type: "text",
    language: "en",
    category: "romantic",
    humorTags: ["romantic", "flirty"],
    humorVector: {romantic: 0.8, teasing: 0.5, silly: 0.35},
    media: {textBody: "Are you Wi-Fi? Because I feel a connection."},
    active: true,
  },
  {
    contentId: "hc_seed_005",
    type: "meme",
    language: "en",
    category: "meme",
    humorTags: ["meme", "relatable"],
    humorVector: {meme: 0.92, situational: 0.6, cringe: 0.2},
    media: {textBody: "Me explaining my sleep schedule to my future self"},
    active: true,
  },
  {
    contentId: "hc_seed_006",
    type: "text",
    language: "tr",
    category: "silly",
    humorTags: ["silly", "everyday"],
    humorVector: {silly: 0.85, situational: 0.5, absurd: 0.25},
    media: {textBody: "Çalar saat değil, moral sabotajcısı."},
    active: true,
  },
  {
    contentId: "hc_seed_007",
    type: "text",
    language: "tr",
    category: "sarcasm",
    humorTags: ["sarcasm"],
    humorVector: {sarcasm: 0.8, dry: 0.5, teasing: 0.35},
    media: {textBody: "Tabii, trafik yine benim yüzümden oluştu."},
    active: true,
  },
  {
    contentId: "hc_seed_008",
    type: "text",
    language: "en",
    category: "dark",
    humorTags: ["dark", "mild"],
    humorVector: {dark: 0.7, dry: 0.55, situational: 0.3},
    media: {textBody: "My plants and I have a mutual neglect agreement."},
    active: true,
  },
  {
    contentId: "hc_seed_009",
    type: "text",
    language: "en",
    category: "teasing",
    humorTags: ["teasing"],
    humorVector: {teasing: 0.85, romantic: 0.4, silly: 0.45},
    media: {textBody: "Nice try. Your poker face is on vacation."},
    active: true,
  },
  {
    contentId: "hc_seed_010",
    type: "text",
    language: "en",
    category: "cringe",
    humorTags: ["cringe", "social"],
    humorVector: {cringe: 0.8, situational: 0.65, silly: 0.4},
    media: {textBody: "Waved at someone who was waving at the person behind me."},
    active: true,
  },
  {
    contentId: "hc_seed_011",
    type: "text",
    language: "tr",
    category: "wordplay",
    humorTags: ["wordplay"],
    humorVector: {wordplay: 0.8, silly: 0.5},
    media: {textBody: "Kahve olmadan ben 'ben' değilim; 'be n'."},
    active: true,
  },
  {
    contentId: "hc_seed_012",
    type: "text",
    language: "en",
    category: "situational",
    humorTags: ["situational", "home"],
    humorVector: {situational: 0.85, absurd: 0.35, dry: 0.4},
    media: {textBody: "Opened the fridge for the third time. Still no new ideas."},
    active: true,
  },
];
