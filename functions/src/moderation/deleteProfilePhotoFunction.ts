import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {deleteProfilePhoto as remove} from "./deleteProfilePhoto.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";

/**
 * Removes one of the caller's own profile photos and everything stored for it.
 *
 * Reads `photoId` from the request and nothing else: the uid comes from the
 * auth context, so a member can only ever name a photo under their own account.
 */
export const deleteProfilePhoto = onCall(
  {enforceAppCheck, region: "europe-west1"},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const data = request.data;
    const photoId = data && typeof data === "object" ? (data as Record<string, unknown>).photoId : undefined;
    return remove(
      {db, bucket: () => getStorage().bucket(), now: () => Date.now()},
      uid,
      {photoId},
    );
  },
);
