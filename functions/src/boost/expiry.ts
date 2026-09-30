import {Timestamp, type Firestore, type QueryDocumentSnapshot} from "firebase-admin/firestore";
import {logger} from "firebase-functions";

/** Kept under the 500-write batch limit. */
export const EXPIRY_PAGE_SIZE = 400;
/** 10,000 Boosts per run; anything beyond waits for the next run. */
export const EXPIRY_MAX_PAGES = 25;

export type ExpiredBoost = {uid: string; boostId: string};

export type ExpiryOptions = {
  now: Timestamp;
  notify: (item: ExpiredBoost) => Promise<void>;
  pageSize?: number;
  maxPages?: number;
};

export type ExpiryResult = {
  expired: number;
  pages: number;
  usedFallback: boolean;
};

/** A composite index that is not deployed (or still building) fails with FAILED_PRECONDITION. */
export function isMissingIndexError(error: unknown): boolean {
  const code = (error as {code?: unknown} | null)?.code;
  return code === 9 || code === "failed-precondition" || code === "FAILED_PRECONDITION";
}

/**
 * Marks due Boosts expired, logs each one and notifies its owner once the
 * write has landed. One batch per call, so callers keep pages <= 500.
 */
async function expireDocs(
  db: Firestore,
  docs: QueryDocumentSnapshot[],
  notify: ExpiryOptions["notify"],
): Promise<void> {
  if (!docs.length) {
    return;
  }
  const expiredDocs: ExpiredBoost[] = [];
  const batch = db.batch();
  for (const doc of docs) {
    batch.update(doc.ref, {status: "expired"});
    expiredDocs.push({uid: String(doc.data().userId ?? ""), boostId: doc.id});
    logger.info("boost_expired", {userId: doc.data().userId, boostId: doc.id});
  }
  await batch.commit();
  for (const item of expiredDocs) {
    if (!item.uid) {
      continue;
    }
    await notify(item);
  }
}

/**
 * The pre-index behaviour: read every active Boost and expire the due ones
 * in memory. Bills one read per live Boost, so it only runs while the
 * (status, expiresAt) collection-group index is missing.
 */
async function expireByFullScan(
  db: Firestore,
  now: Timestamp,
  notify: ExpiryOptions["notify"],
  pageSize: number,
): Promise<number> {
  const snap = await db.collectionGroup("boosts").where("status", "==", "active").get();
  const due = snap.docs.filter((doc) => {
    const expires = doc.data().expiresAt as Timestamp | undefined;
    return Boolean(expires && expires.toMillis() <= now.toMillis());
  });
  for (let i = 0; i < due.length; i += pageSize) {
    await expireDocs(db, due.slice(i, i + pageSize), notify);
  }
  return due.length;
}

/**
 * Expires every active Boost whose `expiresAt` has passed, reading only
 * those. Each page is written before the next is read, so the query drains:
 * expired documents drop out of `status == "active"` and the next page
 * starts at whatever is still due.
 */
export async function expireDueBoosts(db: Firestore, options: ExpiryOptions): Promise<ExpiryResult> {
  const pageSize = options.pageSize ?? EXPIRY_PAGE_SIZE;
  const maxPages = options.maxPages ?? EXPIRY_MAX_PAGES;
  const {now, notify} = options;
  const due = db
    .collectionGroup("boosts")
    .where("status", "==", "active")
    .where("expiresAt", "<=", now)
    .limit(pageSize);

  const seen = new Set<string>();
  let expired = 0;
  let pages = 0;
  while (pages < maxPages) {
    let snap;
    try {
      snap = await due.get();
    } catch (error) {
      if (!isMissingIndexError(error)) {
        throw error;
      }
      logger.warn("boost_expiry_index_missing", {
        fallback: "full_scan",
        pagesDone: pages,
        error: String((error as Error)?.message ?? error),
      });
      const scanned = await expireByFullScan(db, now, notify, pageSize);
      return {expired: expired + scanned, pages, usedFallback: true};
    }
    pages += 1;
    // A document seen twice means the page did not drain; stop rather than loop.
    const fresh = snap.docs.filter((doc) => !seen.has(doc.ref.path));
    fresh.forEach((doc) => seen.add(doc.ref.path));
    await expireDocs(db, fresh, notify);
    expired += fresh.length;
    if (snap.docs.length < pageSize || fresh.length < snap.docs.length) {
      return {expired, pages, usedFallback: false};
    }
  }
  logger.warn("boost_expiry_backlog", {pages, expired, pageSize});
  return {expired, pages, usedFallback: false};
}
