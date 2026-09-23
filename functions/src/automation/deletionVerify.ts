import {getAuth} from "firebase-admin/auth";
import {getFirestore, type Firestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {logger} from "firebase-functions";
import {safeLogMeta} from "../security/logHygiene.js";

export type DeletionVerifyResult = {
  uid: string;
  complete: boolean;
  issues: string[];
  checkedAt: string;
};

/**
 * Documents `deleteUserAccount` removes last. Anything still present here means
 * the deletion transaction did not finish.
 */
const REMNANT_DOC_PATHS = (uid: string): string[] => [
  `users/${uid}`,
  `profiles/${uid}`,
  `userPreferences/${uid}`,
  `userSettings/${uid}`,
  `userPrivacy/${uid}`,
  `userLocation/${uid}`,
  `spotifySecrets/${uid}`,
];

/** Storage prefixes `deleteUserAccount` clears. */
const REMNANT_STORAGE_PREFIXES = (uid: string): string[] => [
  `users/${uid}/`,
  `profiles/${uid}/`,
];

/**
 * Post-deletion verification: Auth gone, core docs gone, Storage empty.
 * Reports gaps only — never deletes, so a partial deletion surfaces for repair
 * or manual review instead of being silently retried destructively.
 */
export async function verifyAccountDeletion(
  uid: string,
  db: Firestore = getFirestore(),
): Promise<DeletionVerifyResult> {
  const issues: string[] = [];

  try {
    await getAuth().getUser(uid);
    issues.push("auth_user_still_exists");
  } catch {
    // Expected: the Auth record is deleted before this job runs.
  }

  for (const path of REMNANT_DOC_PATHS(uid)) {
    if ((await db.doc(path).get()).exists) {
      issues.push(`firestore_remnant:${path}`);
    }
  }

  const [likesFrom, likesTo] = await Promise.all([
    db.collection("likes").where("fromUserId", "==", uid).limit(1).get(),
    db.collection("likes").where("toUserId", "==", uid).limit(1).get(),
  ]);
  if (!likesFrom.empty) {
    issues.push("likes_from_remnant");
  }
  if (!likesTo.empty) {
    issues.push("likes_to_remnant");
  }

  for (const prefix of REMNANT_STORAGE_PREFIXES(uid)) {
    try {
      const [files] = await getStorage().bucket().getFiles({
        prefix,
        maxResults: 5,
        autoPaginate: false,
      });
      if (files.length > 0) {
        issues.push(`storage_remnant:${prefix}`);
      }
    } catch (error) {
      // A Storage outage must not be reported as a clean deletion.
      logger.warn(
        "deletion verify storage check failed",
        safeLogMeta({uid, prefix, error: String(error)}),
      );
      issues.push(`storage_check_failed:${prefix}`);
    }
  }

  return {
    uid,
    complete: issues.length === 0,
    issues,
    checkedAt: new Date().toISOString(),
  };
}
