import {FieldValue, Timestamp, getFirestore, type Firestore} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import {logger} from "firebase-functions";
import type {CleanupOptions, CleanupResult} from "./types.js";

/**
 * Sync premium entitlement: expire subscription/current when expiresAt passed.
 * Clears Auth claim premium when expired. Mutual matches unaffected.
 */
export async function syncExpiredPremium(
  options: CleanupOptions,
  db: Firestore = getFirestore(),
): Promise<CleanupResult> {
  const result: CleanupResult = {
    scanned: 0,
    deleted: 0,
    skipped: 0,
    candidates: [],
    dryRun: options.dryRun,
  };
  const now = Timestamp.now();
  // collectionGroup query on subscription docs named "current"
  const snap = await db
    .collectionGroup("subscription")
    .where("isPremium", "==", true)
    .limit(options.limit)
    .get();

  for (const doc of snap.docs) {
    if (doc.id !== "current") {
      continue;
    }
    result.scanned += 1;
    const data = doc.data();
    const expiresAt = data.expiresAt as Timestamp | undefined;
    if (!expiresAt || expiresAt.toMillis() > now.toMillis()) {
      result.skipped += 1;
      continue;
    }
    const uid = doc.ref.parent.parent?.id;
    if (!uid) {
      result.skipped += 1;
      continue;
    }
    result.candidates.push({uid, expiresAt: expiresAt.toDate().toISOString()});
    if (options.dryRun) {
      continue;
    }
    await doc.ref.set(
      {
        isPremium: false,
        expiredAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    try {
      const user = await getAuth().getUser(uid);
      const claims = {...(user.customClaims ?? {})};
      if (claims.premium === true) {
        delete claims.premium;
        // Preserve admin claim if present.
        await getAuth().setCustomUserClaims(uid, claims);
      }
    } catch (error) {
      logger.warn("premium claim clear skipped", {uid, error: String(error)});
    }
    result.deleted += 1;
  }
  logger.info("syncExpiredPremium", {
    dryRun: options.dryRun,
    scanned: result.scanned,
    expired: result.deleted,
  });
  return result;
}
