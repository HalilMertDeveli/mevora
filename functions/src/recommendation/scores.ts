import {
  DEFAULT_RECOMMENDATION_CONFIG,
  type RecommendationConfig,
} from "./config.js";

/** Clamp into [floor, 1] so multiplicative / weighted blends never wipe a user. */
export function normalizeSignal(
  value: number,
  options: {max?: number; floor?: number} = {},
): number {
  const max = options.max ?? 100;
  const floor = options.floor ?? DEFAULT_RECOMMENDATION_CONFIG.signalFloor;
  if (!Number.isFinite(value) || max <= 0) {
    return floor;
  }
  const unit = Math.min(1, Math.max(0, value / max));
  return Math.max(floor, unit);
}

/** Preference / hard-filter soft score (0–100). Already passed hard filters. */
export function preferenceScoreFromSignals(input: {
  genderMatch?: boolean;
  ageInRange?: boolean;
  distanceKm?: number | null;
  radiusKm?: number | null;
}): number {
  let score = 70;
  if (input.genderMatch === false) {
    return 0;
  }
  if (input.ageInRange === false) {
    return 0;
  }
  const distance = input.distanceKm;
  const radius = input.radiusKm ?? 25;
  if (distance == null || !Number.isFinite(distance) || radius <= 0) {
    return score;
  }
  const ratio = Math.min(1, distance / radius);
  score = Math.round(100 * (1 - ratio * 0.5));
  return Math.max(40, Math.min(100, score));
}

export function activityScoreFromLastActive(
  lastActiveAt: unknown,
  config: RecommendationConfig = DEFAULT_RECOMMENDATION_CONFIG,
  nowMs: number = Date.now(),
): number {
  const ms = toMillis(lastActiveAt);
  if (ms == null) {
    return 55;
  }
  const hours = (nowMs - ms) / (60 * 60 * 1000);
  if (hours <= config.activityFullHours) {
    return 100;
  }
  if (hours <= 72) {
    return 75;
  }
  if (hours <= config.activitySoftDays * 24) {
    return 45;
  }
  if (hours <= 90 * 24) {
    return 25;
  }
  return 15;
}

/**
 * Freshness: new profiles get a controlled lift that decays to the floor.
 * Does not permanently dominate Discover.
 */
export function freshnessScoreFromCreatedAt(
  createdOrUpdatedAt: unknown,
  config: RecommendationConfig = DEFAULT_RECOMMENDATION_CONFIG,
  nowMs: number = Date.now(),
): number {
  const ms = toMillis(createdOrUpdatedAt);
  if (ms == null) {
    return 40;
  }
  const hours = Math.max(0, (nowMs - ms) / (60 * 60 * 1000));
  const halfLife = config.freshnessHalfLifeHours;
  const decay = Math.pow(0.5, hours / halfLife);
  return Math.round(20 + 80 * decay);
}

function toMillis(value: unknown): number | null {
  if (value == null) {
    return null;
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  if (typeof value === "object") {
    const record = value as {toMillis?: () => number; toDate?: () => Date};
    if (typeof record.toMillis === "function") {
      return record.toMillis();
    }
    if (typeof record.toDate === "function") {
      return record.toDate().getTime();
    }
  }
  return null;
}
