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
  if (isBoosted) {
    score += BOOST_PRIORITY_BONUS;
  }
  return score;
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

export function sortByBoostVisibility<T extends Record<string, unknown>>(
  items: T[],
  boosted: Set<string>,
  radiusKm = 25,
): T[] {
  const sorted = [...items].sort((a, b) => {
    const aScore = computeDiscoveryRankScore(a, boosted, radiusKm);
    const bScore = computeDiscoveryRankScore(b, boosted, radiusKm);
    if (bScore !== aScore) {
      return bScore - aScore;
    }
    return Number(b.musicCompatibilityScore ?? 0) -
      Number(a.musicCompatibilityScore ?? 0);
  });
  return diversifyBoostedResults(sorted, boosted);
}

export function isBoostedCandidate(
  uid: string,
  boosted: Set<string>,
): boolean {
  return boosted.has(uid);
}
