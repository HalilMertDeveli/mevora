import {
  HUMOR_CATEGORIES,
  normalizeProfileVector,
  type HumorCategory,
  type HumorVector,
} from "./categories.js";
import {parseCalibrationState} from "./calibration.js";
import {topStrongDims} from "./profile.js";
import {
  HUMOR_PROFILE_BUILDING_THRESHOLD,
  type HumorCompatibilityResult,
  type HumorCompatibilityUnavailableReason,
  type UserHumorProfileDoc,
} from "./types.js";

/** Profile dims live in 0..100; 50 is "no opinion". */
const NEUTRAL = 50;

/**
 * A centred profile whose length is below this has no usable direction: the
 * user rated everything close to neutral, so any cosine against it would be
 * noise dressed up as a score. On the 0..100 scale this is ~3 points of total
 * deviation — a single rating already moves a dimension further than that.
 */
const MIN_CENTRED_NORM = 3;

/** Both sides must sit clearly above neutral for a trait to count as shared. */
const SHARED_TRAIT_MIN = 60;

/** Firestore document id shape accepted for a match id. No `/`, ever. */
const MATCH_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

export function isValidMatchId(value: unknown): value is string {
  return typeof value === "string" && MATCH_ID_PATTERN.test(value);
}

/**
 * Whether a user's initial humor profile is ready to be compared.
 *
 * Mirrors the server's own "profile building" signal: a completed calibration
 * is ready, a calibration in progress is not, and a profile from before
 * structured calibration existed (no current-version progress at all) falls
 * back to the historical interaction threshold.
 */
export function isHumorCalibrationReady(
  calibration: Record<string, unknown> | undefined,
  profile: UserHumorProfileDoc | null | undefined,
): boolean {
  const state = parseCalibrationState(calibration);
  if (state.complete) {
    return true;
  }
  if (state.completedCount > 0) {
    return false;
  }
  return (profile?.interactionCount ?? 0) >= HUMOR_PROFILE_BUILDING_THRESHOLD;
}

export function unavailableHumorCompatibility(
  reason: HumorCompatibilityUnavailableReason,
): HumorCompatibilityResult {
  return {available: false, score: null, strongestShared: [], reason};
}

function centred(vector: HumorVector): HumorVector {
  const out = {...vector};
  for (const dim of HUMOR_CATEGORIES) {
    out[dim] = vector[dim] - NEUTRAL;
  }
  return out;
}

function norm(vector: HumorVector): number {
  let sum = 0;
  for (const dim of HUMOR_CATEGORIES) {
    sum += vector[dim] * vector[dim];
  }
  return Math.sqrt(sum);
}

/**
 * Cosine of two profiles measured from neutral, in [-1, 1], or `null` when
 * either side carries no signal.
 *
 * Raw 0..100 profiles all point the same way (every dimension is positive and
 * most sit near 50), so their plain cosine is ~0.8-1.0 for any pair. Centring
 * on 50 compares what each person actually leans towards or away from.
 */
function centredCosine(a: HumorVector, b: HumorVector): number | null {
  const ca = centred(a);
  const cb = centred(b);
  const normA = norm(ca);
  const normB = norm(cb);
  if (normA < MIN_CENTRED_NORM || normB < MIN_CENTRED_NORM) {
    return null;
  }
  let dot = 0;
  for (const dim of HUMOR_CATEGORIES) {
    dot += ca[dim] * cb[dim];
  }
  return Math.max(-1, Math.min(1, dot / (normA * normB)));
}

/**
 * Traits both sides lean clearly towards, in the caller's (`a`) own order, so
 * the list reveals nothing about how the peer ranks them.
 */
function topKOverlap(
  a: HumorVector,
  b: HumorVector,
  k = 3,
): {score: number; shared: HumorCategory[]} {
  const strongA = topStrongDims(a, SHARED_TRAIT_MIN, HUMOR_CATEGORIES.length);
  const strongB = new Set(topStrongDims(b, SHARED_TRAIT_MIN, HUMOR_CATEGORIES.length));
  const shared = strongA.filter((dim) => strongB.has(dim)).slice(0, k);
  const denom = Math.max(1, Math.min(k, strongA.length, strongB.size));
  return {score: shared.length / denom, shared};
}

function divergencePenalty(a: HumorVector, b: HumorVector): number {
  // Penalize large gaps on dims where either side is extreme.
  let penalty = 0;
  let count = 0;
  for (const dim of HUMOR_CATEGORIES) {
    const av = a[dim];
    const bv = b[dim];
    const gap = Math.abs(av - bv);
    if (av >= 75 || bv >= 75 || av <= 25 || bv <= 25) {
      penalty += gap / 100;
      count += 1;
    }
  }
  if (count === 0) {
    return 0;
  }
  return Math.min(1, penalty / count);
}

/**
 * Pair humor score (0..100). Independent of the overall Compatibility Engine.
 *
 * Formula: 0.70 centred cosine (mapped from [-1, 1] to [0, 1]) + 0.20 shared
 * strong traits + 0.10 (1 - divergence).
 *
 * `profileA` is the caller. The result never carries either side's vector
 * values, confidence or interaction count — only the score and the category
 * keys both sides share.
 *
 * `readiness` says whether each side finished its initial calibration; when
 * omitted, the interaction-count fallback for pre-calibration profiles is used.
 */
export function humorScoreForPair(
  profileA: UserHumorProfileDoc | null | undefined,
  profileB: UserHumorProfileDoc | null | undefined,
  readiness?: {readyA?: boolean; readyB?: boolean},
): HumorCompatibilityResult {
  const readyA = readiness?.readyA ?? isHumorCalibrationReady(undefined, profileA);
  const readyB = readiness?.readyB ?? isHumorCalibrationReady(undefined, profileB);
  if (!profileA || !profileB || !readyA || !readyB) {
    return unavailableHumorCompatibility("building");
  }
  const a = normalizeProfileVector(profileA.vector, NEUTRAL);
  const b = normalizeProfileVector(profileB.vector, NEUTRAL);
  const cosine = centredCosine(a, b);
  if (cosine === null) {
    return unavailableHumorCompatibility("no-signal");
  }
  const similarity = (cosine + 1) / 2;
  const overlap = topKOverlap(a, b);
  const divergence = divergencePenalty(a, b);
  const score = Math.round(
    100 * (0.7 * similarity + 0.2 * overlap.score + 0.1 * (1 - divergence)),
  );
  return {
    available: true,
    score: Math.min(100, Math.max(0, score)),
    strongestShared: overlap.shared,
    reason: null,
  };
}
