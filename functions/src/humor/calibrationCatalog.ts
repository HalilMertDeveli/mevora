import {FieldValue, type Firestore} from "firebase-admin/firestore";
import {isAnchorSlotId} from "./calibration.js";
import {isHumorCategory} from "./categories.js";
import {
  ACTIVE_CALIBRATION_CATALOG,
  CURATED_GIPHY_CATALOG,
  CURATED_GIPHY_ID_PREFIX,
  GIPHY_ID_PATTERN,
  RETIRED_TEXT_JOKE_CONTENT_IDS,
  curatedGiphyContentId,
  curatedGiphyUpsertInput,
  type CalibrationCatalogKind,
  type CuratedGiphyEntry,
} from "./calibrationSeed.js";
import {
  CALIBRATION_ELIGIBLE_FIELD,
  CALIBRATION_SLOT_FIELD,
  CALIBRATION_VERSION_FIELD,
  HUMOR_CONTENT_COLLECTION,
  upsertHumorContentDoc,
  type UpsertHumorContentInput,
} from "./contentRepository.js";
import {mediaUrlProblem} from "./contentValidation.js";
import {MAX_CAPTION_LENGTH} from "./giphySource.js";

/**
 * Seeding the calibration catalogue — shared by the admin
 * `seedInternalHumorContent` callable and `tool/seedEmulatorHumorCatalog.cjs`.
 *
 * Writes the active catalogue (ACTIVE_CALIBRATION_CATALOG) and retires what
 * it replaced. Retiring deactivates and un-curates a document; it never
 * deletes one, so ratings and interactions keep pointing at something real
 * and a revert is just a re-seed. Idempotent: a second run writes the same
 * documents and retires nothing new.
 */

/** The retired text-joke cards, retired by every curated-catalogue seed. */
export const TEXT_JOKE_CONTENT_IDS: readonly string[] = RETIRED_TEXT_JOKE_CONTENT_IDS;

// Kept importable from here, where it always lived.
export {curatedGiphyUpsertInput};

/** Provider-sync doc id of a GIPHY item (same rule as ingest.ts contentIdFor). */
function providerSyncContentId(giphyId: string): string {
  return `ext_giphy_${giphyId}`.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 120);
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

/** Why an entry cannot be seeded; empty when it is well-formed. */
export function curatedGiphyEntryProblems(entry: CuratedGiphyEntry): string[] {
  const problems: string[] = [];
  const id = entry?.giphyId;
  if (!isNonEmptyString(id) || !GIPHY_ID_PATTERN.test(id)) {
    problems.push("giphyId");
    return problems;
  }
  if (entry.contentId !== curatedGiphyContentId(id)) problems.push("contentId");
  if (entry.slot !== undefined) {
    if (!isAnchorSlotId(entry.slot)) problems.push("slot");
    if (entry.calibrationEligible !== true) problems.push("slot-without-eligibility");
  }
  if (typeof entry.calibrationEligible !== "boolean") problems.push("calibrationEligible");
  if (!isHumorCategory(entry.category)) problems.push("category");
  const vector = entry.humorVector ?? {};
  const weights = Object.entries(vector);
  if (
    weights.length === 0 ||
    weights.some(([dim, w]) => !isHumorCategory(dim) || typeof w !== "number" || w < 0 || w > 1)
  ) {
    problems.push("humorVector");
  }
  if (entry.language !== "tr" && entry.language !== "en") problems.push("language");
  if (entry.caption !== null) {
    if (!isNonEmptyString(entry.caption) || entry.caption.length > MAX_CAPTION_LENGTH) {
      problems.push("caption");
    }
  }
  for (const key of ["downloadUrl", "thumbUrl"] as const) {
    const url = entry.media?.[key];
    if (mediaUrlProblem(url) !== null) {
      problems.push(`media.${key}`);
    } else if (!new URL(url).pathname.split("/").includes(id)) {
      // Media must be this item's own rendition, never another clip's.
      problems.push(`media.${key}-not-this-item`);
    }
  }
  const aspect = entry.media?.aspectRatio;
  if (aspect !== null && (typeof aspect !== "number" || !(aspect > 0) || aspect > 10)) {
    problems.push("media.aspectRatio");
  }
  const attribution = entry.attribution;
  if (!attribution || attribution.provider !== "giphy") {
    problems.push("attribution");
  } else if (attribution.sourceUrl !== null) {
    try {
      const page = new URL(attribution.sourceUrl);
      const host = page.hostname.toLowerCase();
      if (page.protocol !== "https:" || !(host === "giphy.com" || host.endsWith(".giphy.com"))) {
        problems.push("attribution.sourceUrl");
      }
    } catch {
      problems.push("attribution.sourceUrl");
    }
  }
  if (entry.sourceTrust !== "curated") problems.push("sourceTrust");
  return problems;
}

export type CalibrationCatalogPlan = {
  kind: CalibrationCatalogKind;
  items: UpsertHumorContentInput[];
  /** Fixed ids this catalogue replaces (reason per id). */
  retire: Array<{contentId: string; reason: string}>;
};

export function calibrationCatalogPlan(
  kind: CalibrationCatalogKind = ACTIVE_CALIBRATION_CATALOG,
  catalog: readonly CuratedGiphyEntry[] = CURATED_GIPHY_CATALOG,
): CalibrationCatalogPlan {
  const invalid = catalog
    .map((entry) => ({entry, problems: curatedGiphyEntryProblems(entry)}))
    .filter((e) => e.problems.length > 0);
  if (invalid.length > 0) {
    throw new Error(
      "curated-giphy-catalog-invalid: " +
        invalid.map((e) => `${e.entry?.contentId ?? "?"} (${e.problems.join(", ")})`).join("; "),
    );
  }
  const ids = catalog.map((e) => e.contentId);
  if (new Set(ids).size !== ids.length) {
    throw new Error("curated-giphy-catalog-invalid: duplicate contentId");
  }
  return {
    kind,
    items: catalog.map(curatedGiphyUpsertInput),
    retire: [
      ...TEXT_JOKE_CONTENT_IDS.map((contentId) => ({contentId, reason: "text-joke-catalog-retired"})),
      // The same clip must not also circulate as an ordinary synced item.
      ...catalog.map((e) => ({
        contentId: providerSyncContentId(e.giphyId),
        reason: "superseded-by-curated",
      })),
    ],
  };
}

export type CalibrationCatalogSeedResult = {
  kind: CalibrationCatalogKind;
  written: number;
  created: number;
  refreshed: number;
  /** Existing docs whose type changed (e.g. a text card rewritten as a GIF). */
  converted: number;
  /** Docs deactivated by this run. */
  retired: number;
  retiredIds: string[];
};

/** Deactivates and un-curates one doc; false when missing or already retired. */
async function retireContent(db: Firestore, contentId: string, reason: string): Promise<boolean> {
  const ref = db.collection(HUMOR_CONTENT_COLLECTION).doc(contentId);
  const snap = await ref.get();
  if (!snap.exists) return false;
  const data = snap.data() ?? {};
  if (data.active !== true && data[CALIBRATION_ELIGIBLE_FIELD] !== true) {
    return false;
  }
  await ref.set(
    {
      active: false,
      [CALIBRATION_ELIGIBLE_FIELD]: false,
      [CALIBRATION_SLOT_FIELD]: null,
      [CALIBRATION_VERSION_FIELD]: 0,
      retiredReason: reason,
      retiredAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  return true;
}

export async function seedCalibrationCatalog(
  db: Firestore,
  options: {kind?: CalibrationCatalogKind; catalog?: readonly CuratedGiphyEntry[]} = {},
): Promise<CalibrationCatalogSeedResult> {
  const plan = calibrationCatalogPlan(options.kind, options.catalog);
  const collection = db.collection(HUMOR_CONTENT_COLLECTION);
  const result: CalibrationCatalogSeedResult = {
    kind: plan.kind,
    written: 0,
    created: 0,
    refreshed: 0,
    converted: 0,
    retired: 0,
    retiredIds: [],
  };

  const keep = new Set(plan.items.map((item) => item.contentId));
  for (const item of plan.items) {
    const before = await collection.doc(item.contentId).get();
    const previous = before.exists ? before.data() ?? {} : null;
    await upsertHumorContentDoc(db, item);
    if (previous && previous.retiredReason != null) {
      // Back in the active catalogue: drop the retirement marker.
      await collection.doc(item.contentId).set({retiredReason: null, retiredAt: null}, {merge: true});
    }
    result.written += 1;
    if (previous) {
      result.refreshed += 1;
      if (previous.type !== item.type) result.converted += 1;
    } else {
      result.created += 1;
    }
  }

  const retire = new Map<string, string>();
  for (const {contentId, reason} of plan.retire) {
    if (!keep.has(contentId)) retire.set(contentId, reason);
  }
  // Curated GIPHY docs that left the catalogue.
  const curated = await collection.where("sourceTrust", "==", "curated").get();
  for (const doc of curated.docs) {
    if (doc.id.startsWith(CURATED_GIPHY_ID_PREFIX) && !keep.has(doc.id) && !retire.has(doc.id)) {
      retire.set(doc.id, "removed-from-curated-catalog");
    }
  }
  for (const [contentId, reason] of retire) {
    if (await retireContent(db, contentId, reason)) {
      result.retired += 1;
      result.retiredIds.push(contentId);
    }
  }
  return result;
}
