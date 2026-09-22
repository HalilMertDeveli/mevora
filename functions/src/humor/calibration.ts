import {
  HUMOR_CATEGORIES,
  normalizeHumorVector,
  normalizeProfileVector,
  type HumorCategory,
} from "./categories.js";
import type {
  HumorCalibrationStage,
  HumorContentDoc,
  UserHumorCalibrationDoc,
  UserHumorProfileDoc,
} from "./types.js";

export type {HumorCalibrationStage, UserHumorCalibrationDoc};

/**
 * Structured initial humor calibration.
 *
 * The lifetime humor profile (`users/{uid}/humor/summary`) keeps learning
 * forever. Calibration is a *milestone* layered on top of it: the first
 * {@link CALIBRATION_TOTAL} rated interactions are drawn from curated pools so
 * that two users' profiles are comparable even though they never see the same
 * memes.
 *
 * Everything in this module is pure and deterministic so the selection policy
 * can be unit tested without Firestore.
 */

export const HUMOR_CALIBRATION_VERSION = 1;

export const ANCHOR_INTERACTIONS = 6;
export const ADAPTIVE_INTERACTIONS = 6;
export const EXPLORATION_INTERACTIONS = 3;
export const CALIBRATION_TOTAL =
  ANCHOR_INTERACTIONS + ADAPTIVE_INTERACTIONS + EXPLORATION_INTERACTIONS;

/**
 * Anchor slot = a measurement role, not a content id. Any curated item tagged
 * with the slot may fill it, which is what lets users receive different memes
 * while staying comparable.
 *
 * Six slots cover eight of the eleven dimensions. `romantic` and `dark` are
 * deliberately excluded from the baseline: both are polarizing enough that a
 * cold reading adds more noise than signal, so they are left to the adaptive
 * and exploration stages where there is already a profile to contrast against.
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

/**
 * Adjacency = dimensions that are easy to confuse with one another. The
 * adaptive stage tests a strong signal against its neighbours, because
 * "likes sarcasm" is only useful once we know whether it is really dry wit,
 * teasing or dark humor underneath.
 */
export const ADJACENT_DIMENSIONS: Readonly<
  Record<HumorCategory, readonly HumorCategory[]>
> = {
  sarcasm: ["dry", "teasing", "dark"],
  absurd: ["silly", "meme"],
  silly: ["absurd", "meme"],
  romantic: ["teasing", "wordplay"],
  dark: ["sarcasm", "absurd"],
  meme: ["silly", "situational", "cringe"],
  dry: ["sarcasm", "situational"],
  wordplay: ["sarcasm", "silly"],
  situational: ["dry", "cringe", "meme"],
  cringe: ["teasing", "situational"],
  teasing: ["cringe", "sarcasm", "romantic"],
};

/**
 * A profile dimension counts as "meaningful signal" once it has moved this far
 * from the neutral 50 midpoint. One `very_funny` rating at the early learning
 * rate moves a dimension by roughly 7 points, so this is about one confident
 * response rather than accumulated drift.
 */
export const ADAPTIVE_SIGNAL_THRESHOLD = 6;

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

/** Stage of the n-th (0-based) upcoming calibration item. */
export function stageForPosition(position: number): HumorCalibrationStage {
  return stageForCompletedCount(position);
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

function orderIndex(dim: HumorCategory): number {
  return HUMOR_CATEGORIES.indexOf(dim);
}

function signalStrength(
  profile: UserHumorProfileDoc,
  dim: HumorCategory,
): number {
  const vector = normalizeProfileVector(profile.vector, 50);
  return Math.abs(vector[dim] - 50);
}

/**
 * Adaptive dimensions for interactions 7–12.
 *
 * Priority order, and why:
 *  1. Neighbours of dimensions the user reacted strongly to — a strong anchor
 *     response is ambiguous until it is separated from its nearest neighbour.
 *  2. Dimensions with no coverage yet — cheap information we simply do not have.
 *  3. Everything else by signal strength, so the run stays deterministic even
 *     on an empty profile.
 *
 * Ties break on the fixed {@link HUMOR_CATEGORIES} order, never on Math.random,
 * so the policy is reproducible in tests and across a resumed session.
 */
export function selectAdaptiveDimensions(input: {
  profile: UserHumorProfileDoc;
  coveredDimensions: readonly string[];
  limit?: number;
}): HumorCategory[] {
  const limit = input.limit ?? ADAPTIVE_INTERACTIONS;
  const covered = new Set(input.coveredDimensions.map((d) => String(d)));
  const chosen: HumorCategory[] = [];

  const push = (dim: HumorCategory): void => {
    if (chosen.length < limit && !chosen.includes(dim)) {
      chosen.push(dim);
    }
  };

  const bySignal = [...HUMOR_CATEGORIES].sort((a, b) => {
    const diff = signalStrength(input.profile, b) - signalStrength(input.profile, a);
    return diff !== 0 ? diff : orderIndex(a) - orderIndex(b);
  });

  // 1. Differentiate strong signals against their neighbours.
  for (const dim of bySignal) {
    if (signalStrength(input.profile, dim) < ADAPTIVE_SIGNAL_THRESHOLD) {
      break;
    }
    for (const neighbour of ADJACENT_DIMENSIONS[dim]) {
      if (!covered.has(neighbour)) {
        push(neighbour);
      }
    }
  }

  // 2. Dimensions we have no evidence for at all.
  for (const dim of bySignal) {
    if (!covered.has(dim)) {
      push(dim);
    }
  }

  // 3. Deterministic backfill so the stage always resolves to `limit` targets.
  for (const dim of bySignal) {
    push(dim);
  }

  return chosen.slice(0, limit);
}

/**
 * Exploration dimensions for interactions 13–15.
 *
 * Deliberately *not* the user's strongest category: this stage exists to stop
 * the profile overfitting to six anchors. It ranks by information gain —
 * uncovered dimensions first, then whichever dimensions sit closest to the
 * neutral midpoint, because those are the ones the profile is least sure about.
 */
export function selectExplorationDimensions(input: {
  profile: UserHumorProfileDoc;
  coveredDimensions: readonly string[];
  limit?: number;
}): HumorCategory[] {
  const limit = input.limit ?? EXPLORATION_INTERACTIONS;
  const covered = new Set(input.coveredDimensions.map((d) => String(d)));

  return [...HUMOR_CATEGORIES]
    .sort((a, b) => {
      const coverA = covered.has(a) ? 1 : 0;
      const coverB = covered.has(b) ? 1 : 0;
      if (coverA !== coverB) {
        return coverA - coverB;
      }
      const evidence =
        signalStrength(input.profile, a) - signalStrength(input.profile, b);
      return evidence !== 0 ? evidence : orderIndex(a) - orderIndex(b);
    })
    .slice(0, limit);
}

/**
 * FNV-1a. Used only to rotate between equivalent curated items — never for
 * anything security-sensitive.
 */
export function stableHash(input: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < input.length; i += 1) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

/**
 * Deterministic rotation across a pool of measurement-equivalent items.
 *
 * Seeded by uid + calibration version + slot, so two users pulling the same
 * anchor slot usually get different content while a single user resuming an
 * interrupted calibration always gets the *same* item back. Resumability and
 * rotation therefore come from the same mechanism, and tests stay deterministic.
 */
export function rotatingIndex(poolSize: number, seed: string): number {
  if (poolSize <= 0) {
    return -1;
  }
  return stableHash(seed) % poolSize;
}

export function rotatingPick<T>(pool: readonly T[], seed: string): T | null {
  const index = rotatingIndex(pool.length, seed);
  return index < 0 ? null : pool[index];
}

/**
 * How well a curated item measures `dimension`. Focused content scores higher
 * than content that spreads its mass across many dimensions, because a diffuse
 * item tells us little about the dimension we are actually probing.
 */
export function scoreCalibrationCandidate(input: {
  content: HumorContentDoc;
  dimension: HumorCategory;
  userLanguages: readonly string[];
}): number {
  const vector = normalizeHumorVector(input.content.humorVector, 0);
  const target = vector[input.dimension];
  let otherMass = 0;
  for (const dim of HUMOR_CATEGORIES) {
    if (dim !== input.dimension) {
      otherMass += vector[dim];
    }
  }
  const focus = target - 0.25 * otherMass;
  const language = input.content.language.trim().toLowerCase();
  const languageBonus = input.userLanguages.some(
    (l) => l.trim().toLowerCase() === language,
  )
    ? 0.25
    : 0;
  return focus + languageBonus;
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
 * Deliberately advances on *any* first-time rating while calibration is
 * incomplete, not only on the item the selector happened to serve. A client
 * holding a stale page would otherwise be able to stall calibration forever,
 * and stage progression stays server-derived either way.
 *
 * Idempotent once complete, and for content already counted — so a retried
 * callable or a re-rating never inflates the count.
 */
export function advanceCalibration(input: {
  state: UserHumorCalibrationDoc;
  content: Pick<HumorContentDoc, "contentId" | "humorVector" | "category" | "calibration">;
}): UserHumorCalibrationDoc {
  const state = input.state;
  if (state.complete || state.completedCount >= CALIBRATION_TOTAL) {
    return state;
  }
  if (state.ratedContentIds.includes(input.content.contentId)) {
    return state;
  }

  const completedCount = Math.min(CALIBRATION_TOTAL, state.completedCount + 1);
  const slot = input.content.calibration?.slot ?? null;
  const coveredSlots =
    input.content.calibration?.eligible === true && isAnchorSlotId(slot)
      ? [...new Set([...state.coveredSlots, String(slot)])].sort()
      : state.coveredSlots;
  const coveredDimensions = [
    ...new Set([...state.coveredDimensions, ...coverageDimensionsOf(input.content)]),
  ].sort();

  return {
    ...state,
    completedCount,
    stage: stageForCompletedCount(completedCount),
    complete: isCalibrationComplete(completedCount),
    ratedContentIds: [...state.ratedContentIds, input.content.contentId],
    coveredSlots,
    coveredDimensions,
    degradedCount:
      input.content.calibration?.eligible === true
        ? state.degradedCount
        : state.degradedCount + 1,
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
};

/** Client-safe projection. Never carries coverage internals or content ids. */
export function toCalibrationView(input: {
  version: number;
  completedCount: number;
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
  };
}
