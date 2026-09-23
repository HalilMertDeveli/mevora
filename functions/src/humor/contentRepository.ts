import {
  FieldValue,
  Timestamp,
  type DocumentData,
  type Firestore,
} from "firebase-admin/firestore";
import {
  isHumorCategory,
  normalizeHumorVector,
  type HumorCategory,
  type HumorVector,
} from "./categories.js";
import {HUMOR_CALIBRATION_VERSION, isAnchorSlotId} from "./calibration.js";
import {CALIBRATION_SEED} from "./calibrationSeed.js";
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

/** Opaque scan position inside the humor catalog. */
export type HumorScanPosition = {
  /** `createdAt` of the last scanned document, as epoch millis. */
  createdAtMs: number;
  /** Document id, breaking ties on identical timestamps. */
  contentId: string;
};

/**
 * A servable item together with its own position in the catalog order.
 *
 * The caller needs per-item positions, not just a page boundary: the feed's
 * cursor must stop after the last item it actually *served*, otherwise every
 * candidate it scanned past but did not serve would be skipped forever.
 */
export type HumorCandidateEntry = {
  content: HumorContentDoc;
  position: HumorScanPosition;
};

export type HumorCandidatePage = {
  entries: HumorCandidateEntry[];
  /** Position after the last document *looked at*, to continue scanning. */
  scannedTo: HumorScanPosition | null;
  /** True when this page reached the end of the catalog. */
  exhausted: boolean;
};

function toMillis(value: unknown): number {
  const candidate = value as {toMillis?: () => number} | null | undefined;
  if (candidate && typeof candidate.toMillis === "function") {
    return candidate.toMillis();
  }
  return 0;
}

/**
 * One ordered page of servable humor content.
 *
 * `listCandidateHumorContent` took an unordered `limit(120)`, which Firestore
 * resolves in `__name__` order — so every call returned the *same* first 120
 * documents however large the catalog grew, and a user who rated them all got
 * an empty feed forever. This walks the catalog instead, newest first,
 * resuming from an explicit position.
 *
 * Ordering by `createdAt` means a document missing that field is invisible to
 * the feed. `upsertHumorContentDoc` always stamps it on create and a test pins
 * that invariant, so the ordering key is safe to rely on.
 */
export async function listHumorContentPage(
  db: Firestore,
  input: {
    languages: string[];
    pageSize: number;
    after?: HumorScanPosition | null;
  },
): Promise<HumorCandidatePage> {
  const languages = input.languages.map((l) => l.toLowerCase()).filter(Boolean);
  const pageSize = Math.min(100, Math.max(10, input.pageSize));

  let query = db
    .collection(HUMOR_CONTENT_COLLECTION)
    .where("active", "==", true)
    .where("safetyStatus", "==", "approved") as FirebaseFirestore.Query;

  // A single preferred language is cheap to push into the query. Two or more
  // are filtered in memory rather than fanning out into an index per pair.
  if (languages.length === 1) {
    query = query.where("language", "==", languages[0]);
  }

  query = query.orderBy("createdAt", "desc").orderBy("__name__", "desc");

  if (input.after) {
    query = query.startAfter(
      Timestamp.fromMillis(input.after.createdAtMs),
      db.collection(HUMOR_CONTENT_COLLECTION).doc(input.after.contentId),
    );
  }

  const snap = await query.limit(pageSize).get();

  // `scannedTo` advances past every document we *looked at*, not just the ones
  // that survived filtering — otherwise a page of wrong-language content would
  // make the scan stall on the same spot forever.
  const lastDoc = snap.docs[snap.docs.length - 1];
  const exhausted = snap.docs.length < pageSize || !lastDoc;
  const scannedTo = exhausted
    ? null
    : {
        createdAtMs: toMillis(lastDoc!.get("createdAt")),
        contentId: lastDoc!.id,
      };

  const entries = snap.docs
    .map((doc) => ({
      content: parseHumorContent(doc.id, doc.data()),
      position: {
        createdAtMs: toMillis(doc.get("createdAt")),
        contentId: doc.id,
      },
    }))
    .filter((entry): entry is HumorCandidateEntry => {
      const item = entry.content;
      if (!item) return false;
      // Re-checked in memory as well as in the query: a fallback path must
      // never be able to serve unapproved content.
      if (!item.active || item.safetyStatus !== "approved") return false;
      if (languages.length > 1 && !languages.includes(item.language)) return false;
      return true;
    });

  return {entries, scannedTo, exhausted};
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

/**
 * Curated calibration catalog, re-exported under its historical name.
 *
 * The content itself now lives in `calibrationSeed.ts`, which keeps curation
 * — what measures what, which slot it fills, how deep each pool is — separate
 * from persistence. `seedInternalHumorContent` is unchanged and still writes
 * exactly this list.
 */
export const INTERNAL_HUMOR_SEED: Array<Omit<UpsertHumorContentInput, "safetyStatus">> =
  CALIBRATION_SEED.map((item) => ({
    contentId: item.contentId,
    type: item.type,
    language: item.language,
    category: item.category,
    humorTags: item.humorTags,
    humorVector: item.humorVector,
    media: item.media,
    active: item.active,
    sourceType: item.sourceType,
    provider: item.provider,
    calibration: item.calibration,
  }));
