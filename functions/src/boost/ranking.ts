import {logger} from "firebase-functions";
import type {Firestore, Timestamp} from "firebase-admin/firestore";

/** Modest priority bump — compatibility stays meaningful. */
export const BOOST_PRIORITY_BONUS = 35;
/** Boosted profiles stay eligible up to +25% beyond viewer radius. */
export const BOOST_DISTANCE_EXTENSION_RATIO = 0.25;
const DISTANCE_SCORE_MAX = 20;

export async function loadActiveBoostedUserIds(
  db: Firestore,
  now = new Date(),
): Promise<Set<string>> {
  try {
    const snap = await db.collectionGroup("boosts").where("status", "==", "active").get();
    const ids = new Set<string>();
    for (const doc of snap.docs) {
      const data = doc.data();
      const expires = data.expiresAt as Timestamp | undefined;
      const expiresAt = expires && typeof expires.toDate === "function" ? expires.toDate() : null;
      if (expiresAt && expiresAt.getTime() > now.getTime() && typeof data.userId === "string") {
        ids.add(data.userId);
      }
    }
    return ids;
  } catch (error) {
    // Missing collection-group index on boosts.status must not empty Discover.
    logger.warn("loadActiveBoostedUserIds_failed", {
      message: error instanceof Error ? error.message : String(error),
    });
    return new Set();
  }
}

export function effectiveRadiusKm(radiusKm: number, isBoosted: boolean): number {
  if (!isBoosted || radiusKm <= 0) {
    return radiusKm;
  }
  return Math.min(100, radiusKm * (1 + BOOST_DISTANCE_EXTENSION_RATIO));
}

export function distanceRankContribution(
  distanceKm: number | null | undefined,
  radiusKm: number,
  isBoosted: boolean,
): number {
  // Unknown distance ranks after any known-distance candidate (even very far).
  if (distanceKm == null || Number.isNaN(distanceKm)) {
    return -2;
  }
  if (radiusKm <= 0) {
    return 0;
  }
  const penaltyFactor = isBoosted ? 0.5 : 1;
  const effectiveDistance = distanceKm * penaltyFactor;
  const normalized = Math.min(1, effectiveDistance / radiusKm);
  return Math.round(DISTANCE_SCORE_MAX * (1 - normalized));
}

/** Ranking score only — never mutates compatibilityScore on the payload. */
export function computeDiscoveryRankScore(
  item: Record<string, unknown>,
  boosted: Set<string>,
  radiusKm: number,
): number {
  const uid = String(item.uid ?? "");
  const isBoosted = boosted.has(uid);
  const compatibility = Number(item.compatibilityScore ?? 0);
  const musicBonus = Number(item.musicRankingBonus ?? 0);
  const distanceKm =
    item.distanceKm == null ? null : Number(item.distanceKm);

  let score = compatibility + musicBonus;
  score += distanceRankContribution(distanceKm, radiusKm, isBoosted);
  // Soft profile-quality lift only (0–4). Never gates Discover eligibility.
  const quality = Number(item.profileQualityScore ?? 0);
  if (Number.isFinite(quality) && quality > 0) {
    score += Math.min(4, Math.floor(quality / 25));
  }
  if (isBoosted) {
    score += BOOST_PRIORITY_BONUS;
  }
  return score;
}

/**
 * Question-answer priority for Discover:
 * 3/3 same answers → highest, then 2/3, 1/3, then everyone else.
 */
export function questionAlignmentTier(item: Record<string, unknown>): number {
  const aligned = Number(item.relationshipAlignedCount ?? 0);
  if (!Number.isFinite(aligned) || aligned <= 0) {
    return 0;
  }
  if (aligned >= 3) {
    return 3;
  }
  if (aligned === 2) {
    return 2;
  }
  return 1;
}

function distanceSortKey(item: Record<string, unknown>): number {
  if (item.distanceKm == null) {
    return Number.POSITIVE_INFINITY;
  }
  const value = Number(item.distanceKm);
  return Number.isFinite(value) ? value : Number.POSITIVE_INFINITY;
}

export function compareDiscoveryCandidates(
  a: Record<string, unknown>,
  b: Record<string, unknown>,
  boosted: Set<string>,
  radiusKm: number,
): number {
  const tierDelta = questionAlignmentTier(b) - questionAlignmentTier(a);
  if (tierDelta !== 0) {
    return tierDelta;
  }
  const distanceDelta = distanceSortKey(a) - distanceSortKey(b);
  if (distanceDelta !== 0) {
    return distanceDelta;
  }
  const aScore = computeDiscoveryRankScore(a, boosted, radiusKm);
  const bScore = computeDiscoveryRankScore(b, boosted, radiusKm);
  if (bScore !== aScore) {
    return bScore - aScore;
  }
  return (
    Number(b.musicCompatibilityScore ?? 0) -
    Number(a.musicCompatibilityScore ?? 0)
  );
}

export function diversifyBoostedResults<T extends Record<string, unknown>>(
  sorted: T[],
  boosted: Set<string>,
): T[] {
  const boostedQueue = sorted.filter((item) => boosted.has(String(item.uid)));
  const normalQueue = sorted.filter((item) => !boosted.has(String(item.uid)));
  if (boostedQueue.length === 0 || normalQueue.length === 0) {
    return sorted;
  }
  const out: T[] = [];
  let boostedIndex = 0;
  let normalIndex = 0;
  while (boostedIndex < boostedQueue.length || normalIndex < normalQueue.length) {
    if (boostedIndex < boostedQueue.length) {
      out.push(boostedQueue[boostedIndex++]);
    }
    if (normalIndex < normalQueue.length) {
      out.push(normalQueue[normalIndex++]);
    }
  }
  return out;
}

/**
 * Primary: more shared question answers.
 * Secondary: closer distance among equal answer tiers.
 * Tertiary: existing boost/compat/music ranking (diversified within tier).
 */
export function sortByBoostVisibility<T extends Record<string, unknown>>(
  items: T[],
  boosted: Set<string>,
  radiusKm = 25,
): T[] {
  const sorted = [...items].sort((a, b) =>
    compareDiscoveryCandidates(a, b, boosted, radiusKm),
  );
  const out: T[] = [];
  for (const tier of [3, 2, 1, 0]) {
    const group = sorted.filter((item) => questionAlignmentTier(item) === tier);
    out.push(...diversifyBoostedResults(group, boosted));
  }
  return out;
}

export function isBoostedCandidate(
  uid: string,
  boosted: Set<string>,
): boolean {
  return boosted.has(uid);
}
