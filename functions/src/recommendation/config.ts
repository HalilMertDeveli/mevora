export type RecommendationWeights = {
  compatibility: number;
  preference: number;
  activity: number;
  profileQuality: number;
  freshness: number;
};

export type RecommendationConfig = {
  weights: RecommendationWeights;
  boostMultiplier: number;
  signalFloor: number;
  freshnessHalfLifeHours: number;
  activityFullHours: number;
  activitySoftDays: number;
};

export const DEFAULT_RECOMMENDATION_CONFIG: RecommendationConfig = {
  weights: {
    compatibility: 0.45,
    preference: 0.2,
    activity: 0.15,
    profileQuality: 0.1,
    freshness: 0.1,
  },
  boostMultiplier: 1.25,
  signalFloor: 0.05,
  freshnessHalfLifeHours: 72,
  activityFullHours: 24,
  activitySoftDays: 14,
};

export function parseRecommendationConfig(raw: unknown): RecommendationConfig {
  const base = DEFAULT_RECOMMENDATION_CONFIG;
  if (!raw || typeof raw !== "object") {
    return base;
  }
  const record = raw as Record<string, unknown>;
  const weightsRaw = (record.weights ?? record) as Record<string, unknown>;
  const weights = {
    compatibility: num(weightsRaw.compatibility, base.weights.compatibility),
    preference: num(weightsRaw.preference, base.weights.preference),
    activity: num(weightsRaw.activity, base.weights.activity),
    profileQuality: num(weightsRaw.profileQuality, base.weights.profileQuality),
    freshness: num(weightsRaw.freshness, base.weights.freshness),
  };
  return {
    weights: normalizeWeights(weights),
    boostMultiplier: clamp(num(record.boostMultiplier, base.boostMultiplier), 1, 1.35),
    signalFloor: clamp(num(record.signalFloor, base.signalFloor), 0.01, 0.2),
    freshnessHalfLifeHours: Math.max(
      1,
      num(record.freshnessHalfLifeHours, base.freshnessHalfLifeHours),
    ),
    activityFullHours: Math.max(1, num(record.activityFullHours, base.activityFullHours)),
    activitySoftDays: Math.max(1, num(record.activitySoftDays, base.activitySoftDays)),
  };
}

function normalizeWeights(weights: RecommendationWeights): RecommendationWeights {
  const sum =
    weights.compatibility +
    weights.preference +
    weights.activity +
    weights.profileQuality +
    weights.freshness;
  if (sum <= 0) {
    return DEFAULT_RECOMMENDATION_CONFIG.weights;
  }
  return {
    compatibility: weights.compatibility / sum,
    preference: weights.preference / sum,
    activity: weights.activity / sum,
    profileQuality: weights.profileQuality / sum,
    freshness: weights.freshness / sum,
  };
}

function num(value: unknown, fallback: number): number {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}
