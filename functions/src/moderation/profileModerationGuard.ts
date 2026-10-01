import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {logger} from "firebase-functions";
import {reconcilePhotoModeration} from "./photoModerationService.js";
import {storedFaceAnchorPhotoIds} from "./photoInvariants.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();

/**
 * Forces profiles/{uid}.photos back onto the server-owned moderation ledger.
 *
 * Firestore rules cannot validate the fields of array elements, so a modified
 * client can write anything into photos[] — including moderationStatus:
 * "approved". This trigger is the authority boundary: every write is
 * reconciled against users/{uid}/photoModeration/{imageId}, which clients
 * cannot write. Nothing in the profile document is trusted.
 *
 * The same pass imposes the Face Anchor rules (photoInvariants.ts): the last
 * verified anchor cannot be removed and the primary photo is always one.
 */
export const enforceProfilePhotoModeration = onDocumentWritten(
  {document: "profiles/{uid}", region: "europe-west1"},
  async (event) => {
    const after = event.data?.after?.data();
    if (!after) {
      return;
    }
    const uid = event.params.uid;
    const hasPhotos = Array.isArray(after.photos) && after.photos.length > 0;
    // An empty array is only interesting when the server knows this profile
    // has an anchor to put back; faceAnchorPhotoIds is not client-writable.
    if (!hasPhotos && storedFaceAnchorPhotoIds(after).length === 0) {
      return;
    }
    let bucket;
    try {
      bucket = getStorage().bucket();
    } catch (error) {
      // Without a bucket the legacy backfill check is skipped; reconciliation
      // still runs and still fails closed.
      logger.warn("Photo reconciliation running without a storage bucket", {
        uid,
        error: String(error),
      });
    }
    const changed = await reconcilePhotoModeration(db, uid, bucket);
    if (changed) {
      logger.warn("Reverted client-written photo moderation state", {uid});
    }
  },
);
