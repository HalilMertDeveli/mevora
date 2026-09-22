import {logger} from "firebase-functions";
import type {Firestore, Timestamp} from "firebase-admin/firestore";

import {BOOST_STRENGTH} from "./config.js";

const DISTANCE_SCORE_MAX = 20;

/**
 * Whether a boosted candidate actually earns its advantage.
 *
 * Buying Boost is necessary but not sufficient: the candidate must also clear
 * the compatibility floor. Without this gate a paid profile with a
 * compatibility of 10 outranks a genuine 95, which makes the number shown to
 * the viewer meaningless. Below the floor a boosted candidate ranks exactly as
 * if it had never bought anything.
 */
export function boostAdvantageApplies(
  item: Record<string, unknown>,
  boosted: Set<string>,
): boolean {
  if (!boosted.has(String(item.uid ?? ""))) {
    return false;
  }
  const compatibility = Number(item.compatibilityScore ?? 0);
  if (!Number.isFinite(compatibility)) {
    return false;
  }
  return compatibility >= BOOST_STRENGTH.minCompatibility;
}

/**
 * Distance as the sort stage sees it — the real distance, for everyone.
 *
 * Boost deliberately does not discount distance here. Distance outranks the
 * score, so any discount would let a boosted profile jump an arbitrarily large
 * compatibility gap, which is exactly what this change exists to stop. Boost's
 * geographic lever is `effectiveRadiusKm`: it widens where a profile is
 * eligible, rather than faking how near it is.
 */
export function boostSortDistanceKm(
  distanceKm: number | null | undefined,
): number {
  if (distanceKm == null) {
    return Number.POSITIVE_INFINITY;
  }
  const value = Number(distanceKm);
  return Number.isFinite(value) ? value : Number.POSITIVE_INFINITY;
}

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
  return Math.min(100, radiusKm * (1 + BOOST_STRENGTH.radiusExtensionRatio));
}

export function distanceRankContribution(
  distanceKm: number | null | undefined,
  radiusKm: number,
): number {
  // Unknown distance ranks after any known-distance candidate (even very far).
  if (distanceKm == null || Number.isNaN(distanceKm)) {
    return -2;
  }
  if (radiusKm <= 0) {
    return 0;
  }
  const normalized = Math.min(1, distanceKm / radiusKm);
  return Math.round(DISTANCE_SCORE_MAX * (1 - normalized));
}

/** Ranking score only — never mutates compatibilityScore on the payload. */
export function computeDiscoveryRankScore(
  item: Record<string, unknown>,
  boosted: Set<string>,
  radiusKm: number,
): number {
  const advantaged = boostAdvantageApplies(item, boosted);
  const compatibility = Number(item.compatibilityScore ?? 0);
  const musicBonus = Number(item.musicRankingBonus ?? 0);
  const distanceKm =
    item.distanceKm == null ? null : Number(item.distanceKm);

  let score = compatibility + musicBonus;
  score += distanceRankContribution(distanceKm, radiusKm);
  if (advantaged) {
    score += BOOST_STRENGTH.priorityBonus;
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
  return boostSortDistanceKm(item.distanceKm as number | null | undefined);
}

/**
 * Total order, so the same inputs always produce the same page.
 *
 * Question alignment, then real distance for everyone, then the rank score —
 * which is where Boost's priority bonus lands. Because the bonus is bounded,
 * a compatibility gap wider than `priorityBonus` still wins, and a
 * non-boosted candidate's keys are identical to what they were before.
 */
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
  const musicDelta =
    Number(b.musicCompatibilityScore ?? 0) -
    Number(a.musicCompatibilityScore ?? 0);
  if (musicDelta !== 0) {
    return musicDelta;
  }
  // Final tiebreak so equal candidates never reorder between requests.
  return String(a.uid ?? "").localeCompare(String(b.uid ?? ""));
}

/**
 * Spaces boosted profiles out without reordering on their behalf.
 *
 * This replaces the previous interleave, which rebuilt the page as
 * boosted/normal/boosted/normal and so discarded every ranking decision the
 * comparator had just made — a boosted profile took the top slot whatever its
 * compatibility, and half of every page went to Boost buyers.
 *
 * Here the sorted order is authoritative. A boosted profile is only ever
 * pushed *later*, never earlier, and only when it would breach the density
 * cap. Deterministic: one pass, stable within each queue.
 */
export function capBoostedDensity<T extends Record<string, unknown>>(
  sorted: T[],
  boosted: Set<string>,
  window: number = BOOST_STRENGTH.densityWindow,
  maxPerWindow: number = BOOST_STRENGTH.maxPerWindow,
): T[] {
  if (window <= 0 || maxPerWindow <= 0) {
    return [...sorted];
  }
  const isAdvantaged = (item: T): boolean => boostAdvantageApplies(item, boosted);
  const out: T[] = [];
  const deferred: T[] = [];

  const windowIsFull = (): boolean => {
    const start = Math.max(0, out.length - window + 1);
    let count = 0;
    for (let i = start; i < out.length; i += 1) {
      if (isAdvantaged(out[i])) {
        count += 1;
      }
    }
    return count >= maxPerWindow;
  };

  for (const item of sorted) {
    if (isAdvantaged(item) && windowIsFull()) {
      deferred.push(item);
      continue;
    }
    out.push(item);
    while (deferred.length > 0 && !windowIsFull()) {
      out.push(deferred.shift() as T);
    }
  }
  out.push(...deferred);
  return out;
}

/**
 * Primary: more shared question answers.
 * Secondary: closer distance, with a boosted profile counted as nearer.
 * Tertiary: compat/music/boost rank score.
 * Finally: boosted profiles spaced out so they cannot fill the page.
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
    out.push(...capBoostedDensity(group, boosted));
  }
  return out;
}

export function isBoostedCandidate(
  uid: string,
  boosted: Set<string>,
): boolean {
  return boosted.has(uid);
}
