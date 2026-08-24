/**
 * Soft distance tiers for discovery fallback.
 * Hard security exclusions stay outside this module.
 */

export type DiscoveryDistanceTier = "nearby" | "extended" | "far" | "no_location";

export type DiscoveryFallbackLevel =
  | "nearby"
  | "extended"
  | "far"
  | "no_location"
  | "empty";

/** Absolute ceiling for "extended" soft include (km). */
export const DISCOVERY_EXTENDED_CAP_KM = 100;
/** Soft include beyond extended until this (km). */
export const DISCOVERY_FAR_CAP_KM = 500;

/**
 * Classify a candidate relative to the viewer's preferred radius.
 * Null distance (viewer or candidate missing location) → no_location.
 */
export function classifyDiscoveryDistance(
  distanceKm: number | null,
  radiusKm: number,
  isBoosted: boolean,
  effectiveRadius: number,
): DiscoveryDistanceTier {
  if (distanceKm == null || Number.isNaN(distanceKm)) {
    return "no_location";
  }
  if (distanceKm <= effectiveRadius) {
    return "nearby";
  }
  const extended = Math.max(radiusKm, DISCOVERY_EXTENDED_CAP_KM);
  if (distanceKm <= extended) {
    return "extended";
  }
  if (distanceKm <= DISCOVERY_FAR_CAP_KM) {
    return "far";
  }
  // Extremely far — still usable as last-resort far tier.
  return "far";
}

/**
 * Fill the result page from distance tiers without dropping everyone
 * just because they are outside the preferred radius.
 */
export function fillFromDistanceTiers<T>(
  buckets: Record<DiscoveryDistanceTier, T[]>,
  limit: number,
): {items: T[]; fallbackLevel: DiscoveryFallbackLevel} {
  const order: DiscoveryDistanceTier[] = [
    "nearby",
    "extended",
    "far",
    "no_location",
  ];
  const items: T[] = [];
  let deepest: DiscoveryFallbackLevel = "empty";

  for (const tier of order) {
    for (const item of buckets[tier]) {
      if (items.length >= limit) {
        break;
      }
      items.push(item);
      deepest = tier;
    }
    if (items.length >= limit) {
      break;
    }
  }

  if (items.length === 0) {
    return {items, fallbackLevel: "empty"};
  }
  return {items, fallbackLevel: deepest};
}

/** Escalation ladder for client retries when a radius still returns empty. */
export function nextDiscoveryRadiusKm(currentKm: number): number | null {
  const ladder = [5, 10, 25, 50, 100];
  const index = ladder.indexOf(currentKm);
  if (index < 0) {
    return currentKm < 100 ? 100 : null;
  }
  if (index >= ladder.length - 1) {
    return null;
  }
  return ladder[index + 1];
}
