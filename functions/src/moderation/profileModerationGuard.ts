import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {stripClientModerationEscalations} from "./photoModerationService.js";
import type {PhotoRecord} from "./types.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();

function photosFrom(data: Record<string, unknown> | undefined): PhotoRecord[] {
  return ((data?.photos as PhotoRecord[] | undefined) ?? []).map((photo) => ({...photo}));
}

export const enforceProfilePhotoModeration = onDocumentWritten(
  {document: "profiles/{uid}", region: "europe-west1"},
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!after) {
      return;
    }
    const uid = event.params.uid;
    const beforePhotos = photosFrom(before);
    const afterPhotos = photosFrom(after);
    if (!beforePhotos.length && !afterPhotos.length) {
      return;
    }
    const blocked = await stripClientModerationEscalations(db, uid, beforePhotos, afterPhotos);
    if (blocked) {
      logger.warn("Blocked client-side photo moderation escalation", {uid});
    }
  },
);
