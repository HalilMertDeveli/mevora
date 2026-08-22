import type {Firestore, Timestamp} from "firebase-admin/firestore";

const BOOST_RANK_BONUS = 1000;

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

export function sortByBoostVisibility<T extends Record<string, unknown>>(
  items: T[],
  boosted: Set<string>,
): T[] {
  return [...items].sort((a, b) => {
    const aBoost = boosted.has(String(a.uid)) ? BOOST_RANK_BONUS : 0;
    const bBoost = boosted.has(String(b.uid)) ? BOOST_RANK_BONUS : 0;
    if (aBoost !== bBoost) {
      return bBoost - aBoost;
    }
    const aRank =
      Number(a.compatibilityScore ?? 0) + Number(a.musicRankingBonus ?? 0);
    const bRank =
      Number(b.compatibilityScore ?? 0) + Number(b.musicRankingBonus ?? 0);
    if (bRank !== aRank) {
      return bRank - aRank;
    }
    return Number(b.musicCompatibilityScore ?? 0) -
      Number(a.musicCompatibilityScore ?? 0);
  });
}
