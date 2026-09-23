import {FieldValue, type DocumentData, type Firestore} from "firebase-admin/firestore";
import {
  isHumorCategory,
  normalizeHumorVector,
  type HumorCategory,
  type HumorVector,
} from "./categories.js";
import {HUMOR_CALIBRATION_VERSION, isAnchorSlotId} from "./calibration.js";
import {classifyHumorSafety, emptySafetyFlags} from "./moderation.js";
import {resolveHumorSourceAdapter} from "./sourceAdapter.js";
import type {
  HumorCalibrationMeta,
  HumorCalibrationStage,
  HumorContentDoc,
  HumorContentType,
  HumorFeedItem,
  HumorMedia,
  HumorSafetyFlags,
  HumorSafetyStatus,
} from "./types.js";

export const HUMOR_CONTENT_COLLECTION = "humorContent";

/**
 * Calibration curation is stored as three flat fields rather than a nested map
 * so the pools stay directly queryable without a map-field index per slot.
 */
export const CALIBRATION_ELIGIBLE_FIELD = "calibrationEligible";
export const CALIBRATION_SLOT_FIELD = "calibrationSlot";
export const CALIBRATION_VERSION_FIELD = "calibrationVersion";

export function toFeedSafeContent(
  doc: HumorContentDoc,
  calibrationStage: HumorCalibrationStage | null = null,
): HumorFeedItem {
  return {
    contentId: doc.contentId,
    type: doc.type,
    language: doc.language,
    category: doc.category,
    humorTags: doc.humorTags,
    // Stage only. The anchor slot id and the curation flags stay server-side.
    calibrationStage,
    media: {
      downloadUrl: doc.media?.downloadUrl ?? null,
      thumbUrl: doc.media?.thumbUrl ?? null,
      durationMs: doc.media?.durationMs ?? null,
      aspectRatio: doc.media?.aspectRatio ?? null,
      textBody: doc.media?.textBody ?? null,
    },
  };
}

/**
 * Closed by default: an item is calibration-eligible only if it explicitly says
 * so, and a slot is honoured only on an eligible item. Bulk provider ingest
 * writes neither field, so it can never present itself as a curated anchor.
 */
export function parseCalibrationMeta(data: DocumentData): HumorCalibrationMeta {
  const eligible = data[CALIBRATION_ELIGIBLE_FIELD] === true;
  const slotRaw = data[CALIBRATION_SLOT_FIELD];
  const slot =
    eligible && typeof slotRaw === "string" && slotRaw.trim().length > 0
      ? slotRaw.trim()
      : null;
  const version = Number(data[CALIBRATION_VERSION_FIELD] ?? 0);
  return {eligible, slot, version: Number.isFinite(version) ? version : 0};
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
    calibration: parseCalibrationMeta(data),
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

/**
 * Curated calibration pool.
 *
 * `slot` selects an anchor pool; omitting it returns the whole eligible pool,
 * which is what the adaptive and exploration stages draw from. Serving rules
 * (active + approved) are re-checked in memory as well as in the query, so a
 * missing index falling back to the broad scan cannot serve unapproved content.
 *
 * Results are sorted by content id to give the deterministic rotation selector
 * a stable pool ordering regardless of query plan.
 */
export async function listCalibrationPool(
  db: Firestore,
  input: {slot?: string | null; limit?: number; calibrationVersion: number},
): Promise<HumorContentDoc[]> {
  const limit = Math.min(200, Math.max(input.limit ?? 60, 10));
  const slot = input.slot ?? null;

  const keep = (item: HumorContentDoc | null): item is HumorContentDoc => {
    if (!item) return false;
    if (!item.active || item.safetyStatus !== "approved") return false;
    if (!item.calibration.eligible) return false;
    if (item.calibration.version !== input.calibrationVersion) return false;
    if (slot !== null && item.calibration.slot !== slot) return false;
    return true;
  };

  const run = async (build: () => FirebaseFirestore.Query): Promise<HumorContentDoc[]> => {
    const snap = await build().get();
    return snap.docs
      .map((doc) => parseHumorContent(doc.id, doc.data()))
      .filter(keep)
      .sort((a, b) => (a.contentId < b.contentId ? -1 : a.contentId > b.contentId ? 1 : 0));
  };

  try {
    return await run(() => {
      let query = db
        .collection(HUMOR_CONTENT_COLLECTION)
        .where(CALIBRATION_ELIGIBLE_FIELD, "==", true)
        .where("active", "==", true)
        .where("safetyStatus", "==", "approved");
      if (slot !== null) {
        query = query.where(CALIBRATION_SLOT_FIELD, "==", slot);
      }
      return query.limit(limit);
    });
  } catch {
    // Composite index missing: fall back to the eligibility filter alone and
    // let `keep` enforce the rest.
    return run(() =>
      db
        .collection(HUMOR_CONTENT_COLLECTION)
        .where(CALIBRATION_ELIGIBLE_FIELD, "==", true)
        .limit(limit),
    );
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
  /** Explicit calibration curation. Absent means "not calibration content". */
  calibration?: {eligible: boolean; slot?: string | null; version?: number};
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
  // Curation is opt-in and only meaningful on approved content: an item that is
  // not servable must not sit in a calibration pool waiting to be served.
  const calibrationEligible =
    input.calibration?.eligible === true && safetyStatus === "approved";
  const calibrationSlot =
    calibrationEligible && isAnchorSlotId(input.calibration?.slot)
      ? String(input.calibration?.slot)
      : null;
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
    [CALIBRATION_ELIGIBLE_FIELD]: calibrationEligible,
    [CALIBRATION_SLOT_FIELD]: calibrationSlot,
    [CALIBRATION_VERSION_FIELD]: calibrationEligible
      ? (input.calibration?.version ?? HUMOR_CALIBRATION_VERSION)
      : 0,
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
const INTERNAL_HUMOR_SEED_ITEMS: Array<Omit<UpsertHumorContentInput, "safetyStatus">> = [
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

  // --- Calibration alternates -------------------------------------------
  // A second measurement-equivalent item per anchor slot, so the rotation
  // selector has something to rotate between and two users calibrated on the
  // same slot need not watch the same asset. Plus one `dry`-dominant item,
  // which the original seed had no focused candidate for.
  {
    contentId: "hc_tr_img_006",
    type: "meme",
    language: "tr",
    category: "sarcasm",
    humorTags: ["ironi", "gunluk"],
    humorVector: {sarcasm: 0.86, dry: 0.5, situational: 0.35},
    media: {
      downloadUrl: "https://picsum.photos/seed/mevora-tr-6/1080/1920",
      thumbUrl: "https://picsum.photos/seed/mevora-tr-6/540/960",
      aspectRatio: 9 / 16,
      textBody: "Harika, tam da bugün bitmesi gereken şey bitmedi.",
    },
    active: true,
  },
  {
    contentId: "hc_tr_vid_006",
    type: "video",
    language: "tr",
    category: "absurd",
    humorTags: ["absürt", "video"],
    humorVector: {absurd: 0.87, silly: 0.55},
    media: {
      downloadUrl:
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4",
      thumbUrl:
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ElephantsDream.jpg",
      durationMs: 15000,
      aspectRatio: 16 / 9,
      textBody: "Rüyamda da sıra bekliyordum. Uyanınca da.",
    },
    active: true,
  },
  {
    contentId: "hc_tr_img_007",
    type: "image",
    language: "tr",
    category: "situational",
    humorTags: ["günlük", "sosyal"],
    humorVector: {situational: 0.85, cringe: 0.4, dry: 0.35},
    media: {
      downloadUrl: "https://picsum.photos/seed/mevora-tr-7/1080/1920",
      thumbUrl: "https://picsum.photos/seed/mevora-tr-7/540/960",
      aspectRatio: 9 / 16,
      textBody: "Asansörde sohbet başlatan insan türü üzerine bir inceleme.",
    },
    active: true,
  },
  {
    contentId: "hc_tr_img_008",
    type: "meme",
    language: "tr",
    category: "meme",
    humorTags: ["meme", "klasik"],
    humorVector: {meme: 0.88, silly: 0.45},
    media: {
      downloadUrl: "https://picsum.photos/seed/mevora-tr-8/1080/1920",
      thumbUrl: "https://picsum.photos/seed/mevora-tr-8/540/960",
      aspectRatio: 9 / 16,
      textBody: "Bildirimi kapattım, huzur geldi sandım. Gelmedi.",
    },
    active: true,
  },
  {
    contentId: "hc_tr_img_009",
    type: "image",
    language: "tr",
    category: "wordplay",
    humorTags: ["kelime", "espri"],
    humorVector: {wordplay: 0.87, sarcasm: 0.4},
    media: {
      downloadUrl: "https://picsum.photos/seed/mevora-tr-9/1080/1920",
      thumbUrl: "https://picsum.photos/seed/mevora-tr-9/540/960",
      aspectRatio: 9 / 16,
      textBody: "Planım yoktu ama planım olmadığına dair bir planım vardı.",
    },
    active: true,
  },
  {
    contentId: "hc_tr_img_010",
    type: "meme",
    language: "tr",
    category: "cringe",
    humorTags: ["cringe", "sosyal"],
    humorVector: {cringe: 0.85, teasing: 0.45, situational: 0.5},
    media: {
      downloadUrl: "https://picsum.photos/seed/mevora-tr-10/1080/1920",
      thumbUrl: "https://picsum.photos/seed/mevora-tr-10/540/960",
      aspectRatio: 9 / 16,
      textBody: "Sesli mesajı yanlış gruba attım. İyi geceler herkese.",
    },
    active: true,
  },
  {
    contentId: "hc_tr_img_011",
    type: "image",
    language: "tr",
    category: "dry",
    humorTags: ["kuru", "sakin"],
    humorVector: {dry: 0.86, situational: 0.4},
    media: {
      downloadUrl: "https://picsum.photos/seed/mevora-tr-11/1080/1920",
      thumbUrl: "https://picsum.photos/seed/mevora-tr-11/540/960",
      aspectRatio: 9 / 16,
      textBody: "Evet. Güzel. Devam edelim.",
    },
    active: true,
  },
];

/**
 * Calibration curation for the internal seed.
 *
 * Kept as an explicit table rather than a field on each item so that "which
 * content is trusted as an anchor" is reviewable in one place — and so the
 * default for anything absent from this table is, correctly, *not* eligible.
 *
 * Each anchor slot has two measurement-equivalent candidates; the rest of the
 * eligible pool feeds the adaptive and exploration stages, which select by
 * dimension rather than by slot.
 */
const INTERNAL_SEED_CALIBRATION: Readonly<
  Record<string, {eligible: boolean; slot?: string | null}>
> = {
  // Anchor slots — two equivalent candidates each.
  hc_tr_img_001: {eligible: true, slot: "anchor_wit"},
  hc_tr_img_006: {eligible: true, slot: "anchor_wit"},
  hc_tr_vid_001: {eligible: true, slot: "anchor_absurd"},
  hc_tr_vid_006: {eligible: true, slot: "anchor_absurd"},
  hc_tr_vid_002: {eligible: true, slot: "anchor_everyday"},
  hc_tr_img_007: {eligible: true, slot: "anchor_everyday"},
  hc_tr_vid_004: {eligible: true, slot: "anchor_meme"},
  hc_tr_img_008: {eligible: true, slot: "anchor_meme"},
  hc_tr_img_002: {eligible: true, slot: "anchor_wordplay"},
  hc_tr_img_009: {eligible: true, slot: "anchor_wordplay"},
  hc_tr_img_004: {eligible: true, slot: "anchor_social"},
  hc_tr_img_010: {eligible: true, slot: "anchor_social"},
  // Adaptive / exploration pool — eligible, but never an anchor.
  hc_tr_vid_003: {eligible: true, slot: null},
  hc_tr_vid_005: {eligible: true, slot: null},
  hc_tr_img_003: {eligible: true, slot: null},
  hc_tr_img_005: {eligible: true, slot: null},
  hc_tr_img_011: {eligible: true, slot: null},
  hc_en_vid_001: {eligible: true, slot: null},
  hc_en_img_001: {eligible: true, slot: null},
};

export const INTERNAL_HUMOR_SEED: Array<Omit<UpsertHumorContentInput, "safetyStatus">> =
  INTERNAL_HUMOR_SEED_ITEMS.map((item) => ({
    ...item,
    calibration: INTERNAL_SEED_CALIBRATION[item.contentId] ?? {eligible: false},
  }));
