import {
  HUMOR_CATEGORIES,
  normalizeHumorVector,
  type HumorCategory,
} from "./categories.js";
import type {
  HumorCalibrationStage,
  HumorContentDoc,
  UserHumorCalibrationDoc,
} from "./types.js";

export type {HumorCalibrationStage, UserHumorCalibrationDoc};

/**
 * Structured initial humor calibration.
 *
 * The lifetime humor profile (`users/{uid}/humor/summary`) keeps learning
 * forever. Calibration is a *milestone* layered on top of it: the first
 * {@link CALIBRATION_TOTAL} counted ratings of curated content.
 *
 * Which content those are is no longer decided here. Every member rates the
 * same canonical Core sequence (`coreSequence.ts`, `coreSchedule.ts`); this
 * module only keeps the milestone document — the count the rest of the
 * backend reads as "this profile is ready" — and the curation vocabulary
 * (anchor slots, coverage) the catalogue is described in.
 *
 * Everything in this module is pure and deterministic.
 */

export const HUMOR_CALIBRATION_VERSION = 1;

/**
 * Stage boundaries of the milestone count. They once selected content (six
 * anchors, six adaptive picks, three exploration picks); now they only label
 * how far the count has come, for the stored document and for clients that
 * still read `stage`. The total must equal `HUMOR_CORE.onboardingCount`.
 */
export const ANCHOR_INTERACTIONS = 6;
export const ADAPTIVE_INTERACTIONS = 6;
export const EXPLORATION_INTERACTIONS = 3;
export const CALIBRATION_TOTAL =
  ANCHOR_INTERACTIONS + ADAPTIVE_INTERACTIONS + EXPLORATION_INTERACTIONS;

/**
 * Anchor slot = a measurement role a curated item is tagged with. The Core
 * sequence opens with one item per slot, so every member's first six ratings
 * cover the same baseline.
 *
 * Coverage, stated precisely because the two numbers differ:
 *
 * - The slot table *declares* nine of the eleven dimensions (six `primary`
 *   plus `dry`, `silly`, `teasing` as contrasts). `romantic` and `dark` are
 *   deliberately excluded from the baseline: both are polarizing enough that a
 *   cold reading adds more noise than signal, so they are left to the adaptive
 *   and exploration stages where there is already a profile to contrast
 *   against.
 * - What the six anchors actually *measure* is eight dimensions, because
 *   coverage is computed from the curated item's vector mass
 *   (>= {@link COVERAGE_MASS_THRESHOLD}), not from this table. No current
 *   `anchor_social` candidate carries enough `teasing` mass to clear the
 *   threshold, so `teasing` is declared but unmeasured and falls to the
 *   adaptive stage — which is exactly where an uncovered dimension should go.
 *
 * `contrast` is a declarative design note: it records which neighbour a slot
 * exists to separate its `primary` from. Nothing reads it at runtime, so
 * it constrains curation review rather than behaviour. The measured
 * set is pinned by a test so it cannot drift silently.
 *
 * `dry` appears only as a contrast dimension because in isolation it is very
 * hard to distinguish from a weak `sarcasm` response.
 */
export type HumorAnchorSlot = {
  readonly id: string;
  /** Dimension the slot is meant to measure. */
  readonly primary: HumorCategory;
  /** Nearest neighbour the slot is meant to separate `primary` from. */
  readonly contrast: HumorCategory;
};

export const ANCHOR_SLOTS: readonly HumorAnchorSlot[] = [
  {id: "anchor_wit", primary: "sarcasm", contrast: "dry"},
  {id: "anchor_absurd", primary: "absurd", contrast: "silly"},
  {id: "anchor_everyday", primary: "situational", contrast: "dry"},
  {id: "anchor_meme", primary: "meme", contrast: "silly"},
  {id: "anchor_wordplay", primary: "wordplay", contrast: "sarcasm"},
  {id: "anchor_social", primary: "cringe", contrast: "teasing"},
] as const;

export const ANCHOR_SLOT_IDS: readonly string[] = ANCHOR_SLOTS.map((s) => s.id);

export function isAnchorSlotId(value: unknown): boolean {
  return typeof value === "string" && ANCHOR_SLOT_IDS.includes(value);
}

/** Content counts as evidence for a dimension at this vector mass or above. */
export const COVERAGE_MASS_THRESHOLD = 0.5;

export function stageForCompletedCount(
  completedCount: number,
): HumorCalibrationStage {
  const done = Math.max(0, Math.floor(completedCount));
  if (done < ANCHOR_INTERACTIONS) {
    return "anchor";
  }
  if (done < ANCHOR_INTERACTIONS + ADAPTIVE_INTERACTIONS) {
    return "adaptive";
  }
  if (done < CALIBRATION_TOTAL) {
    return "exploration";
  }
  return "complete";
}

export function isCalibrationComplete(completedCount: number): boolean {
  return stageForCompletedCount(completedCount) === "complete";
}

/**
 * Curated for *this* calibration version. Only such content may count toward
 * an anchor position or add measurement coverage.
 */
export function isCalibrationCurated(
  content: Pick<HumorContentDoc, "calibration">,
): boolean {
  return (
    content.calibration?.eligible === true &&
    content.calibration.version === HUMOR_CALIBRATION_VERSION
  );
}

/** Dimensions a content item provides real evidence for. */
export function coverageDimensionsOf(
  content: Pick<HumorContentDoc, "humorVector" | "category">,
): HumorCategory[] {
  const vector = normalizeHumorVector(content.humorVector, 0);
  const dims = HUMOR_CATEGORIES.filter(
    (dim) => vector[dim] >= COVERAGE_MASS_THRESHOLD,
  );
  if (dims.length > 0) {
    return dims;
  }
  // Vector-less curated content still measures its declared category.
  return HUMOR_CATEGORIES.includes(content.category) ? [content.category] : [];
}

export function defaultCalibrationState(): UserHumorCalibrationDoc {
  return {
    version: HUMOR_CALIBRATION_VERSION,
    completedCount: 0,
    stage: "anchor",
    complete: false,
    ratedContentIds: [],
    coveredSlots: [],
    coveredDimensions: [],
    degradedCount: 0,
  };
}

/** Normalize a persisted document, tolerating partial/legacy shapes. */
export function parseCalibrationState(
  data: Record<string, unknown> | undefined,
): UserHumorCalibrationDoc {
  const base = defaultCalibrationState();
  if (!data) {
    return base;
  }
  const version = Number(data.version ?? base.version);
  // A document written by a newer/older calibration version is not replayable
  // against this policy, so it restarts rather than corrupting the coverage
  // bookkeeping. The lifetime profile is untouched by this.
  if (!Number.isFinite(version) || version !== HUMOR_CALIBRATION_VERSION) {
    return base;
  }
  const completedCount = Math.min(
    CALIBRATION_TOTAL,
    Math.max(0, Math.floor(Number(data.completedCount ?? 0)) || 0),
  );
  const strings = (value: unknown): string[] =>
    Array.isArray(value) ? value.map((v) => String(v)).filter(Boolean) : [];
  return {
    version: HUMOR_CALIBRATION_VERSION,
    completedCount,
    stage: stageForCompletedCount(completedCount),
    complete: isCalibrationComplete(completedCount),
    ratedContentIds: strings(data.ratedContentIds),
    coveredSlots: strings(data.coveredSlots),
    coveredDimensions: strings(data.coveredDimensions),
    degradedCount: Math.max(0, Math.floor(Number(data.degradedCount ?? 0)) || 0),
    startedAt: data.startedAt,
    completedAt: data.completedAt,
  };
}

/**
 * Fold one newly rated item into calibration state.
 *
 * Advances on any first-time rating of *curated* content while calibration is
 * incomplete, not only on the item the selector happened to serve: a client
 * holding a stale page must not be able to stall calibration, and stage
 * progression stays server-derived either way.
 *
 * Uncurated (provider / legacy) content never adds coverage and never claims
 * an anchor position — the six anchors are the comparable baseline. It may
 * fill an adaptive/exploration position, and an anchor position only when the
 * caller established that no curated candidate is left for this user
 * (`allowUncuratedAnchor`), so an exhausted pool degrades instead of
 * dead-ending. Every such position — and an anchor position that did not
 * measure a new slot — is counted in `degradedCount`.
 *
 * Idempotent once complete, and for content already counted — so a retried
 * callable or a re-rating never inflates the count.
 */
export function advanceCalibration(input: {
  state: UserHumorCalibrationDoc;
  content: Pick<HumorContentDoc, "contentId" | "humorVector" | "category" | "calibration">;
  allowUncuratedAnchor?: boolean;
}): UserHumorCalibrationDoc {
  const state = input.state;
  if (state.complete || state.completedCount >= CALIBRATION_TOTAL) {
    return state;
  }
  if (state.ratedContentIds.includes(input.content.contentId)) {
    return state;
  }

  const curated = isCalibrationCurated(input.content);
  const stage = stageForCompletedCount(state.completedCount);
  if (!curated && stage === "anchor" && input.allowUncuratedAnchor !== true) {
    return state;
  }

  const completedCount = Math.min(CALIBRATION_TOTAL, state.completedCount + 1);
  const slot = curated ? input.content.calibration.slot : null;
  const fillsNewSlot =
    isAnchorSlotId(slot) && !state.coveredSlots.includes(String(slot));
  const coveredSlots = fillsNewSlot
    ? [...new Set([...state.coveredSlots, String(slot)])].sort()
    : state.coveredSlots;
  const coveredDimensions = curated
    ? [
        ...new Set([...state.coveredDimensions, ...coverageDimensionsOf(input.content)]),
      ].sort()
    : state.coveredDimensions;
  const degraded = !curated || (stage === "anchor" && !fillsNewSlot);

  return {
    ...state,
    completedCount,
    stage: stageForCompletedCount(completedCount),
    complete: isCalibrationComplete(completedCount),
    ratedContentIds: [...state.ratedContentIds, input.content.contentId],
    coveredSlots,
    coveredDimensions,
    degradedCount: degraded ? state.degradedCount + 1 : state.degradedCount,
  };
}

/**
 * Persistable fields only.
 *
 * `parseCalibrationState` carries `startedAt` / `completedAt` straight from the
 * snapshot, so they are `undefined` on a document that has not stamped them
 * yet — and Firestore rejects `undefined`. Spreading the parsed state into a
 * write therefore fails from the second rating onward. Building the payload
 * explicitly keeps the timestamps under the caller's control.
 */
export function calibrationWritePayload(
  state: UserHumorCalibrationDoc,
): Record<string, unknown> {
  return {
    version: state.version,
    completedCount: state.completedCount,
    stage: state.stage,
    complete: state.complete,
    ratedContentIds: state.ratedContentIds,
    coveredSlots: state.coveredSlots,
    coveredDimensions: state.coveredDimensions,
    degradedCount: state.degradedCount,
  };
}

export type CalibrationStateView = {
  version: number;
  stage: HumorCalibrationStage;
  completedCount: number;
  totalCount: number;
  complete: boolean;
  /**
   * Some position was filled below the designed measurement quality (thin
   * curated pool, uncurated content). For QA / ops visibility only: the client
   * parser ignores it and it must never reach user-facing copy.
   */
  degraded: boolean;
};

/** Client-safe projection. Never carries coverage internals or content ids. */
export function toCalibrationView(input: {
  version: number;
  completedCount: number;
  degradedCount?: number;
}): CalibrationStateView {
  const completedCount = Math.min(
    CALIBRATION_TOTAL,
    Math.max(0, Math.floor(input.completedCount)),
  );
  return {
    version: input.version,
    stage: stageForCompletedCount(completedCount),
    completedCount,
    totalCount: CALIBRATION_TOTAL,
    complete: isCalibrationComplete(completedCount),
    degraded: (Math.floor(Number(input.degradedCount ?? 0)) || 0) > 0,
  };
}
