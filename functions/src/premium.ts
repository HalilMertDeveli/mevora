import {getAuth} from "firebase-admin/auth";
import {getFirestore, type Timestamp} from "firebase-admin/firestore";

/**
 * Premium entitlement without a full billing system.
 * Sources (any one is enough):
 * 1) Auth custom claim `premium === true`
 * 2) users/{uid}/subscription/current with isPremium and optional expiresAt
 */
export async function isUserPremium(uid: string): Promise<boolean> {
  try {
    const user = await getAuth().getUser(uid);
    if (user.customClaims?.premium === true) {
      return true;
    }
  } catch {
    // Fall through to Firestore subscription doc.
  }

  const snap = await getFirestore().doc(`users/${uid}/subscription/current`).get();
  if (!snap.exists) {
    return false;
  }
  const data = snap.data() ?? {};
  if (data.isPremium !== true) {
    return false;
  }
  const expires = data.expiresAt as Timestamp | undefined;
  if (expires && typeof expires.toMillis === "function") {
    return expires.toMillis() > Date.now();
  }
  return true;
}
