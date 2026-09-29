import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {recordCheckIn} from "./service.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";
const callableOptions = {enforceAppCheck, region: "europe-west1" as const};

/**
 * Daily streak check-in for the signed-in member.
 *
 * The uid comes from the verified ID token and nothing else; the only input
 * the client supplies is its UTC offset, which picks where the member's day
 * boundary falls — never which day it is. Engagement metadata only: nothing
 * in matching, Picks, Boost or compatibility reads the streak.
 */
export const recordDailyCheckIn = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  const data = (request.data ?? {}) as Record<string, unknown>;
  return recordCheckIn(db, {uid, timezoneOffsetMinutes: data.timezoneOffsetMinutes});
});
