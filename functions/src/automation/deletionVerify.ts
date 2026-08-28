import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore, type Firestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {logger} from "firebase-functions";

export type DeletionVerifyResult = {
  uid: string;
  complete: boolean;
  issues: string[];
  checkedAt: string;
};

/**
 * Post-deletion verification: Auth gone, core docs gone, Storage empty.
 * Does not delete — reports gaps for repair / manual review.
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
    // expected — user deleted
  }

  const paths = [
    `users/${uid}`,
    `profiles/${uid}`,
    `userPreferences/${uid}`,
    `userSettings/${uid}`,
    `userPrivacy/${uid}`,
    `userLocation/${uid}`,
    `spotifySecrets/${uid}`,
  ];
  for (const path of paths) {
    if ((await db.doc(path).get()).exists) {
      issues.push(`firestore_remnant:${path}`);
    }
  }

  const likesFrom = await db.collection("likes").where("fromUserId", "==", uid).limit(1).get();
  if (!likesFrom.empty) {
    issues.push("likes_from_remnant");
  }
  const likesTo = await db.collection("likes").where("toUserId", "==", uid).limit(1).get();
  if (!likesTo.empty) {
    issues.push("likes_to_remnant");
  }

  const discoverable = await db.doc(`profiles/${uid}`).get();
  if (discoverable.exists && discoverable.data()?.isDiscoverable === true) {
    issues.push("still_discoverable");
  }

  try {
    const [files] = await getStorage().bucket().getFiles({
      prefix: `users/${uid}/`,
      maxResults: 5,
      autoPaginate: false,
    });
    if (files.length > 0) {
      issues.push(`storage_remnants:${files.length}+`);
    }
  } catch (error) {
    logger.warn("deletion verify storage check failed", {uid, error: String(error)});
  }

  const result: DeletionVerifyResult = {
    uid,
    complete: issues.length === 0,
    issues,
    checkedAt: new Date().toISOString(),
  };

  await db.doc(`automationJobs/deletion_verify_${uid}`).set(
    {
      kind: "account_deletion_verify",
      status: result.complete ? "succeeded" : "manual_review",
      result,
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );

  return result;
}

/**
 * Safe repair for incomplete user documents after signup.
 * Only fills missing non-privileged fields — never sets ban/premium/admin.
 */
export async function repairUserDocument(
  uid: string,
  db: Firestore = getFirestore(),
): Promise<{repaired: boolean; actions: string[]}> {
  const actions: string[] = [];
  const userRef = db.doc(`users/${uid}`);
  const snap = await userRef.get();
  if (!snap.exists) {
    await userRef.set(
      {
        uid,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        accountStatus: "active",
        lastActiveAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    actions.push("created_user_stub");
  } else {
    const data = snap.data() ?? {};
    const patch: Record<string, unknown> = {};
    if (!data.uid) {
      patch.uid = uid;
    }
    if (!data.accountStatus) {
      patch.accountStatus = "active";
    }
    if (Object.keys(patch).length) {
      patch.updatedAt = FieldValue.serverTimestamp();
      await userRef.set(patch, {merge: true});
      actions.push("patched_user_fields");
    }
  }
  return {repaired: actions.length > 0, actions};
}
