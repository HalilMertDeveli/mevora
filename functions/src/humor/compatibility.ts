import {
  HUMOR_CATEGORIES,
  normalizeProfileVector,
  type HumorCategory,
} from "./categories.js";
import {cosineSimilarity, topStrongDims} from "./profile.js";
import type {HumorCompatibilityResult, UserHumorProfileDoc} from "./types.js";

const MIN_INTERACTIONS = 8;
const MIN_CONFIDENCE = 0.15;

function topKOverlap(
  a: ReturnType<typeof normalizeProfileVector>,
  b: ReturnType<typeof normalizeProfileVector>,
  min = 70,
  k = 3,
): {score: number; shared: HumorCategory[]} {
  const strongA = new Set(topStrongDims(a, min, 11));
  const strongB = topStrongDims(b, min, 11);
  const shared = strongB.filter((dim) => strongA.has(dim)).slice(0, k);
  const denom = Math.max(1, Math.min(k, strongA.size, strongB.length || 1));
  return {score: shared.length / denom, shared};
}

function divergencePenalty(
  a: ReturnType<typeof normalizeProfileVector>,
  b: ReturnType<typeof normalizeProfileVector>,
): number {
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

function differenceRows(
  a: ReturnType<typeof normalizeProfileVector>,
  b: ReturnType<typeof normalizeProfileVector>,
  limit = 3,
): Array<{dim: HumorCategory; a: number; b: number}> {
  return HUMOR_CATEGORIES
    .map((dim) => ({dim, a: a[dim], b: b[dim], gap: Math.abs(a[dim] - b[dim])}))
    .filter((row) => row.gap >= 20)
    .sort((x, y) => y.gap - x.gap)
    .slice(0, limit)
    .map(({dim, a: av, b: bv}) => ({dim, a: av, b: bv}));
}

/**
 * Pair humor score (0..100). Independent of overall Compatibility Engine in MVP.
 * Formula: 0.70 cosine + 0.20 topK overlap + 0.10 (1 - divergence).
 */
export function humorScoreForPair(
  profileA: UserHumorProfileDoc | null | undefined,
  profileB: UserHumorProfileDoc | null | undefined,
): HumorCompatibilityResult {
  if (!profileA || !profileB) {
    return {
      available: false,
      score: null,
      strongestShared: [],
      differences: [],
      confidence: 0,
      reason: "missing-profile",
    };
  }
  const conf = Math.min(profileA.confidence ?? 0, profileB.confidence ?? 0);
  if (
    (profileA.interactionCount ?? 0) < MIN_INTERACTIONS ||
    (profileB.interactionCount ?? 0) < MIN_INTERACTIONS ||
    conf < MIN_CONFIDENCE
  ) {
    return {
      available: false,
      score: null,
      strongestShared: [],
      differences: [],
      confidence: conf,
      reason: "building",
    };
  }
  const a = normalizeProfileVector(profileA.vector, 50);
  const b = normalizeProfileVector(profileB.vector, 50);
  const cosine = cosineSimilarity(a, b);
  const overlap = topKOverlap(a, b);
  const divergence = divergencePenalty(a, b);
  const score = Math.round(
    100 * (0.7 * cosine + 0.2 * overlap.score + 0.1 * (1 - divergence)),
  );
  return {
    available: true,
    score: Math.min(100, Math.max(0, score)),
    strongestShared: overlap.shared,
    differences: differenceRows(a, b),
    confidence: conf,
  };
}
