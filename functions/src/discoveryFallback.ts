/**
 * Distance handling for discovery.
 *
 * Two different jobs live here, and confusing them is how the gate went
 * missing for so long:
 *
 *  - isWithinDiscoveryRadius / resolveDiscoveryRadiusKm are the HARD gate.
 *    They decide who is in the deck at all.
 *  - classifyDiscoveryDistance / fillFromDistanceTiers are SOFT tiers. They
 *    only order the people the gate already admitted, and by design they
 *    never reject anyone.
 *
 * Hard security exclusions (blocks, bans, moderation) stay outside this
 * module.
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
 * Hard ceiling for discovery. A candidate further than this is EXCLUDED from
 * the response — not ranked last, excluded. The soft tiers above only decide
 * the order of the people who already passed this gate.
 *
 * 100 km deliberately matches MAX_RELATIONSHIP_MATCH_KM
 * (relationshipCompatibility.ts) and DISTANCE_MAX_DISCLOSED_KM
 * (geo/coarseDistance.ts): one number for "too far to date", one number the
 * product already discloses, and the value the radius ladder already tops out
 * at.
 */
export const DISCOVERY_MAX_RADIUS_KM = 100;

/**
 * Resolve the hard gate for one request. The caller-supplied radius is the
 * progressive step — the client walks it up the ladder (5/10/25/50/100) when a
 * deck comes back empty — and this clamps it to the absolute ceiling so no
 * request can widen the gate past what the product allows.
 */
export function resolveDiscoveryRadiusKm(requestedKm: unknown): number {
  const value = Number(requestedKm);
  if (!Number.isFinite(value) || value <= 0) {
    return DISCOVERY_MAX_RADIUS_KM;
  }
  return Math.min(value, DISCOVERY_MAX_RADIUS_KM);
}

/**
 * The hard gate itself.
 *
 * Takes the EXACT haversine distance, never the disclosed bucket: the bucket
 * is floored to 5 km bands and flattened at 100, so gating on it would admit
 * anyone at all beyond 100 km (100 <= 100) — precisely the hole this function
 * exists to close.
 *
 * A null distance means the viewer or the candidate has no stored location, so
 * proximity cannot be asserted either way. What to do with those candidates is
 * a policy decision left to the caller; this predicate only reports that they
 * are not verifiably within range.
 */
export function isWithinDiscoveryRadius(
  exactDistanceKm: number | null,
  radiusKm: number,
): boolean {
  if (exactDistanceKm == null || !Number.isFinite(exactDistanceKm)) {
    return false;
  }
  return exactDistanceKm <= radiusKm;
}

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
  // No rejecting branch on purpose: by the time a candidate reaches this
  // function the hard gate in getDiscoveryCandidates has already dropped
  // anyone out of range, so everything left is includable and this only
  // picks an ordering bucket. Do not turn this into an exclusion — the gate
  // needs the exact haversine, which is no longer in scope here.
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
