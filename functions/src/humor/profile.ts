import {
  emptyHumorVector,
  clamp01,
  clampProfileValue,
  exactProfileVector,
  isHumorCategory,
  normalizeHumorVector,
  HUMOR_CATEGORIES,
  type HumorCategory,
  type HumorVector,
} from "./categories.js";
import {
  HUMOR_PROFILE_BUILDING_THRESHOLD,
  HUMOR_PROFILE_VERSION,
  type HumorRating,
  type UserHumorProfileDoc,
} from "./types.js";

/** Rating → signed weight for EMA update. */
export const RATING_WEIGHTS: Record<HumorRating, number> = {
  very_funny: 1.0,
  funny: 0.6,
  neutral: 0.0,
  not_funny: -0.5,
  not_at_all: -1.0,
};

export function ratingWeight(rating: HumorRating): number {
  return RATING_WEIGHTS[rating] ?? 0;
}

export function confidenceFromInteractions(interactionCount: number): number {
  const n0 = 40;
  const count = Math.max(0, interactionCount);
  return clamp01(1 - Math.exp(-count / n0));
}

/**
 * Step size while the profile is young: the first {@link YOUNG_PROFILE_RATINGS}
 * counted ratings — the initial calibration — each move a fully-weighted
 * dimension this far toward its target.
 *
 * It has to be large. Calibration is 15 ratings spread over 11 dimensions, so
 * a dimension is typically measured by only one to three focused items. With
 * the old 0.15 step two confident ratings could not lift a dimension past the
 * client's "medium" (60) bucket, and the result screen had nothing to say.
 */
export const YOUNG_LEARNING_RATE = 0.45;

/** Counted ratings that learn at the full {@link YOUNG_LEARNING_RATE}. */
export const YOUNG_PROFILE_RATINGS = 15;

/**
 * Floor for mature profiles. Learning never stops: interaction 500 still
 * moves a fully-weighted dimension by this fraction of its distance to target.
 */
export const MATURE_LEARNING_RATE = 0.08;

/**
 * Step size for the `countedIndex`-th counted rating (1-based).
 *
 * Flat while young, then a harmonic decay (0.45·15/k) — the step a running
 * mean would take — down to {@link MATURE_LEARNING_RATE}, so an established
 * profile is refined rather than overwritten by its latest rating.
 */
export function learningRate(countedIndex: number): number {
  const k = Math.max(1, Math.floor(Number.isFinite(countedIndex) ? countedIndex : 1));
  if (k <= YOUNG_PROFILE_RATINGS) {
    return YOUNG_LEARNING_RATE;
  }
  return Math.max(
    MATURE_LEARNING_RATE,
    (YOUNG_LEARNING_RATE * YOUNG_PROFILE_RATINGS) / k,
  );
}

/**
 * Mass an item without any usable vector contributes to its declared
 * category — roughly what a focused curated item carries.
 */
const CATEGORY_FALLBACK_MASS = 0.8;

/** Per-dimension change one rating applied to the stored vector. */
export type HumorProfileDelta = Partial<Record<HumorCategory, number>>;

/** Tolerant read of a persisted `appliedDelta` map. */
export function parseProfileDelta(raw: unknown): HumorProfileDelta {
  const out: HumorProfileDelta = {};
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return out;
  }
  for (const dim of HUMOR_CATEGORIES) {
    const value = (raw as Record<string, unknown>)[dim];
    if (typeof value === "number" && Number.isFinite(value)) {
      out[dim] = value;
    }
  }
  return out;
}

/** Dimensions the content actually carries, with their 0..1 mass. */
function contentMass(
  contentVector: HumorVector | Partial<HumorVector>,
  category: string | undefined,
): Partial<Record<HumorCategory, number>> {
  const vector = normalizeHumorVector(contentVector, 0);
  const mass: Partial<Record<HumorCategory, number>> = {};
  for (const dim of HUMOR_CATEGORIES) {
    if (vector[dim] > 0) {
      mass[dim] = vector[dim];
    }
  }
  if (Object.keys(mass).length === 0 && category && isHumorCategory(category)) {
    mass[category] = CATEGORY_FALLBACK_MASS;
  }
  return mass;
}

export function isProfileBuilding(interactionCount: number): boolean {
  return interactionCount < HUMOR_PROFILE_BUILDING_THRESHOLD;
}

export function defaultUserHumorProfile(): UserHumorProfileDoc {
  return {
    vector: emptyHumorVector(50),
    confidence: 0,
    interactionCount: 0,
    exploredCategories: [],
    version: HUMOR_PROFILE_VERSION,
  };
}

/**
 * One rating's effect on the lifetime profile.
 *
 * For every dimension `d` the content carries (mass `m = contentVector[d] > 0`):
 *
 *   profile[d] ← profile[d] + α·m·(50 + 50·w − profile[d])
 *
 * - Only the dimensions the content carries move. A sarcasm clip says nothing
 *   about romantic humor, so it no longer drags `romantic` back toward 50 —
 *   the old update did exactly that on every rating, which is why fifteen
 *   ratings could never produce a visible trait.
 * - The target depends on the rating alone (very_funny → 100, not_at_all → 0,
 *   neutral → 50); the content's mass scales how far this one item may move
 *   the dimension, so a secondary tag moves it less than the item's focus.
 * - α comes from {@link learningRate}: large during calibration, decaying for
 *   mature profiles.
 * - Stored values keep full precision; views round.
 *
 * `mode: "replace"` is a *changed* rating on already-counted content: the
 * previous rating's `previousDelta` is subtracted first and the new rating is
 * applied at the same step, without counting a second interaction. Rating A
 * very_funny and then changing it to not_at_all therefore ends where a single
 * not_at_all would have.
 */
export function applyRatingToProfile(input: {
  profile: UserHumorProfileDoc;
  contentVector: HumorVector | Partial<HumorVector>;
  category?: string;
  rating: HumorRating;
  mode?: "first" | "replace";
  previousDelta?: HumorProfileDelta | null;
}): {profile: UserHumorProfileDoc; appliedDelta: HumorProfileDelta} {
  const prev = input.profile;
  const replacing = input.mode === "replace";
  const prevCount = Math.max(0, Math.floor(Number(prev.interactionCount ?? 0)) || 0);
  const nextCount = replacing ? Math.max(1, prevCount) : prevCount + 1;
  const vector = exactProfileVector(prev.vector, 50);

  if (replacing && input.previousDelta) {
    for (const dim of HUMOR_CATEGORIES) {
      const delta = input.previousDelta[dim];
      if (typeof delta === "number" && Number.isFinite(delta)) {
        vector[dim] = clampProfileValue(vector[dim] - delta);
      }
    }
  }

  const alpha = learningRate(nextCount);
  const target = 50 + 50 * ratingWeight(input.rating);
  const mass = contentMass(input.contentVector, input.category);
  const appliedDelta: HumorProfileDelta = {};
  for (const dim of HUMOR_CATEGORIES) {
    const m = mass[dim];
    if (!m) {
      continue;
    }
    const before = vector[dim];
    const after = clampProfileValue(before + alpha * m * (target - before));
    vector[dim] = after;
    appliedDelta[dim] = after - before;
  }

  const explored = new Set(
    (prev.exploredCategories ?? []).map((c) => String(c).trim()).filter(Boolean),
  );
  if (input.category) {
    explored.add(input.category);
  }
  return {
    profile: {
      vector,
      confidence: confidenceFromInteractions(nextCount),
      interactionCount: nextCount,
      exploredCategories: [...explored].sort(),
      version: HUMOR_PROFILE_VERSION,
    },
    appliedDelta,
  };
}

/** A first rating of new content: counts one interaction. */
export function applyFeedbackToProfile(input: {
  profile: UserHumorProfileDoc;
  contentVector: HumorVector | Partial<HumorVector>;
  category?: string;
  rating: HumorRating;
}): UserHumorProfileDoc {
  return applyRatingToProfile({...input, mode: "first"}).profile;
}

/** Cosine similarity of two profile (0..100) or content (0..1) vectors. */
export function cosineSimilarity(a: HumorVector, b: HumorVector): number {
  let dot = 0;
  let normA = 0;
  let normB = 0;
  for (const dim of HUMOR_CATEGORIES) {
    const av = a[dim];
    const bv = b[dim];
    dot += av * bv;
    normA += av * av;
    normB += bv * bv;
  }
  if (normA <= 0 || normB <= 0) {
    return 0;
  }
  return clamp01(dot / (Math.sqrt(normA) * Math.sqrt(normB)));
}

/** Affinity between profile (0..100) and content vector (0..1). */
export function affinityScore(profile: HumorVector, content: HumorVector): number {
  const scaled = emptyHumorVector(0);
  for (const dim of HUMOR_CATEGORIES) {
    scaled[dim] = profile[dim] / 100;
  }
  return cosineSimilarity(scaled, content);
}

export function topStrongDims(
  vector: HumorVector,
  min = 70,
  limit = 3,
): HumorCategory[] {
  return HUMOR_CATEGORIES
    .map((dim) => ({dim, value: vector[dim]}))
    .filter((row) => row.value >= min)
    .sort((a, b) => b.value - a.value)
    .slice(0, limit)
    .map((row) => row.dim);
}
