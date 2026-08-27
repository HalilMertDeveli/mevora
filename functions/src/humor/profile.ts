import {
  emptyHumorVector,
  clamp01,
  clamp100,
  normalizeHumorVector,
  normalizeProfileVector,
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

/** Rating → signed weight for EMA update. Binary UI uses funny / not_funny (±1). */
export const RATING_WEIGHTS: Record<HumorRating, number> = {
  very_funny: 1.0,
  funny: 1.0,
  neutral: 0.0,
  not_funny: -1.0,
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

export function learningRate(confidence: number): number {
  // Early: faster learning; mature: slower.
  return 0.15 - 0.1 * clamp01(confidence);
}

export function isProfileBuilding(interactionCount: number): boolean {
  return interactionCount < HUMOR_PROFILE_BUILDING_THRESHOLD;
}

export function defaultUserHumorProfile(): UserHumorProfileDoc {
  return {
    vector: emptyHumorVector(50),
    confidence: 0,
    interactionCount: 0,
    funnyCount: 0,
    notFunnyCount: 0,
    exploredCategories: [],
    version: HUMOR_PROFILE_VERSION,
  };
}

/**
 * EMA update: profile[d] ← (1-α)·profile[d] + α·(50 + 50·w·contentVector[d])
 * Profile dims stay in 0..100.
 */
export function applyFeedbackToProfile(input: {
  profile: UserHumorProfileDoc;
  contentVector: HumorVector | Partial<HumorVector>;
  category?: string;
  rating: HumorRating;
}): UserHumorProfileDoc {
  const prev = input.profile;
  const contentVec = normalizeHumorVector(input.contentVector, 0);
  const profileVec = normalizeProfileVector(prev.vector, 50);
  const w = ratingWeight(input.rating);
  const nextCount = Math.max(0, (prev.interactionCount ?? 0) + 1);
  const confidence = confidenceFromInteractions(nextCount);
  const alpha = learningRate(confidence);
  const nextVector = emptyHumorVector(50);
  for (const dim of HUMOR_CATEGORIES) {
    const signal = w * contentVec[dim];
    const target = 50 + 50 * signal;
    nextVector[dim] = clamp100((1 - alpha) * profileVec[dim] + alpha * target);
  }
  const explored = new Set(
    (prev.exploredCategories ?? []).map((c) => String(c).trim()).filter(Boolean),
  );
  if (input.category) {
    explored.add(input.category);
  }
  return {
    vector: nextVector,
    confidence,
    interactionCount: nextCount,
    funnyCount: Math.max(0, Number(prev.funnyCount ?? 0)),
    notFunnyCount: Math.max(0, Number(prev.notFunnyCount ?? 0)),
    exploredCategories: [...explored].sort(),
    version: HUMOR_PROFILE_VERSION,
  };
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
