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
  `users/${uid}/verification/identity`,
  `users/${uid}/verification/sumsub`,
  // Learned recommendation preferences. A late like/match trigger could
  // re-create it after the sweep, so it is checked, not assumed.
  `users/${uid}/personalization/profile`,
  // Their Relationship Learning answers. An in-flight answer save could
  // re-create it, so it is checked, not assumed.
  `users/${uid}/relationshipLearning/state`,
  // Humor state is an inferred personality profile. An in-flight humor call
  // can re-create these after the sweep, so they are checked, not assumed.
  `users/${uid}/humor/summary`,
  `users/${uid}/humor/calibration`,
  // Their own Mevora Picks batch: who they were shown, and why.
  `users/${uid}/mevoraPicks/current`,
  // Daily streak: engagement history. The check-in refuses to write once the
  // account document is gone, but a call in flight is checked, not assumed.
  `users/${uid}/dailyStreak/current`,
  // The admin console's name-search row; the profile trigger could recreate
  // it if a profile write raced the deletion, so it is checked.
  `adminUserLookup/${uid}`,
];

/** Storage prefixes `deleteUserAccount` clears. */
const REMNANT_STORAGE_PREFIXES = (uid: string): string[] => [
  `users/${uid}/`,
  `profiles/${uid}/`,
  `moderation/quarantine/${uid}/`,
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

  // Another member's Picks still recommending (or cooling down) this account.
  const inboundPicks = await db
    .collectionGroup("mevoraPicks")
    .where("candidateUids", "array-contains", uid)
    .limit(1)
    .get();
  if (!inboundPicks.empty) {
    issues.push("inbound_picks_remnant");
  }

  const [humorInteractions, humorReports, humorQueuePointer] = await Promise.all([
    db.collection(`users/${uid}/humorInteractions`).limit(1).get(),
    db.collection("humorReports").where("reporterId", "==", uid).limit(1).get(),
    db.collection("humorModerationQueue").where("lastReporterId", "==", uid).limit(1).get(),
  ]);
  if (!humorInteractions.empty) {
    issues.push("humor_interactions_remnant");
  }
  if (!humorReports.empty) {
    issues.push("humor_reports_remnant");
  }
  if (!humorQueuePointer.empty) {
    issues.push("humor_queue_reporter_remnant");
  }

  // Appeals are the member's own words; they go with the account.
  const appeals = await db.collection("appeals").where("userId", "==", uid).limit(1).get();
  if (!appeals.empty) {
    issues.push("appeals_remnant");
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
