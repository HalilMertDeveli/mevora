import {
  DEFAULT_RECOMMENDATION_CONFIG,
  type RecommendationConfig,
} from "./config.js";
import {
  activityScoreFromLastActive,
  freshnessScoreFromCreatedAt,
  normalizeSignal,
  preferenceScoreFromSignals,
} from "./scores.js";

export {DEFAULT_RECOMMENDATION_CONFIG};

export type RecommendationScoreInput = {
  compatibilityScore: number;
  preferenceScore?: number;
  activityScore?: number;
  profileQualityScore?: number;
  freshnessScore?: number;
  lastActiveAt?: unknown;
  createdAt?: unknown;
  updatedAt?: unknown;
  genderMatch?: boolean;
  ageInRange?: boolean;
  distanceKm?: number | null;
  radiusKm?: number | null;
  isBoosted?: boolean;
};

/**
 * Weighted base score (0–100) then optional boost multiplier.
 * Compatibility is the largest weight. Boost never bypasses hard filters —
 * callers must filter first, then rank.
 */
export function computeRecommendationScore(
  input: RecommendationScoreInput,
  config: RecommendationConfig = DEFAULT_RECOMMENDATION_CONFIG,
  nowMs: number = Date.now(),
): {
  baseScore: number;
  finalScore: number;
  boostMultiplier: number;
  signals: Record<string, number>;
} {
  const floor = config.signalFloor;
  const preferenceRaw =
    input.preferenceScore ??
    preferenceScoreFromSignals({
      genderMatch: input.genderMatch,
      ageInRange: input.ageInRange,
      distanceKm: input.distanceKm,
      radiusKm: input.radiusKm,
    });
  const activityRaw =
    input.activityScore ??
    activityScoreFromLastActive(input.lastActiveAt, config, nowMs);
  const freshnessRaw =
    input.freshnessScore ??
    freshnessScoreFromCreatedAt(input.createdAt ?? input.updatedAt, config, nowMs);
  const qualityRaw = input.profileQualityScore ?? 60;
  const signals = {
    compatibility: normalizeSignal(input.compatibilityScore, {floor}),
    preference: normalizeSignal(preferenceRaw, {floor}),
    activity: normalizeSignal(activityRaw, {floor}),
    profileQuality: normalizeSignal(qualityRaw, {floor}),
    freshness: normalizeSignal(freshnessRaw, {floor}),
  };
  const w = config.weights;
  const baseUnit =
    signals.compatibility * w.compatibility +
    signals.preference * w.preference +
    signals.activity * w.activity +
    signals.profileQuality * w.profileQuality +
    signals.freshness * w.freshness;
  const baseScore = Math.round(baseUnit * 1000) / 10;
  const boostMultiplier = input.isBoosted ? config.boostMultiplier : 1;
  const finalScore = Math.round(baseScore * boostMultiplier * 10) / 10;
  return {baseScore, finalScore, boostMultiplier, signals};
}

/**
 * Controlled exploration: swap a small fraction of mid-rank slots with
 * lower-ranked but fresher / diverse candidates without violating hard filters
 * (caller already filtered the list).
 */
export function applyControlledExploration<T>(
  ranked: T[],
  options: {
    exploreRatio?: number;
    seed?: number;
    freshnessOf: (item: T) => number;
  },
): T[] {
  if (ranked.length < 6) {
    return ranked;
  }
  const ratio = Math.min(0.15, Math.max(0, options.exploreRatio ?? 0.08));
  const swaps = Math.max(1, Math.floor(ranked.length * ratio));
  const out = [...ranked];
  let seed = options.seed ?? ranked.length;
  const rand = () => {
    seed = (seed * 1664525 + 1013904223) >>> 0;
    return seed / 0xffffffff;
  };
  for (let i = 0; i < swaps; i++) {
    const from = Math.floor(ranked.length * 0.2 + rand() * ranked.length * 0.3);
    const to = Math.floor(ranked.length * 0.55 + rand() * ranked.length * 0.35);
    if (from >= out.length || to >= out.length || from === to) {
      continue;
    }
    if (options.freshnessOf(out[to]) >= options.freshnessOf(out[from])) {
      const tmp = out[from];
      out[from] = out[to];
      out[to] = tmp;
    }
  }
  return out;
}
