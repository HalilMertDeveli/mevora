import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {answersFromSummary} from "../relationshipCompatibility.js";
import {profileQualityFromDocs} from "./profileQuality.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";
const callableOptions = {
  region: "europe-west1" as const,
  invoker: "public" as const,
  enforceAppCheck,
};

/**
 * Owner-facing Profile Quality Score from live Firestore docs.
 * Does not change onboarding requirements or Discover eligibility.
 */
export const getProfileQualityScore = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "unauthenticated");
  }

  const [profileSnap, userSnap, musicSnap, summarySnap, answersSnap] =
    await Promise.all([
      db.doc(`profiles/${uid}`).get(),
      db.doc(`users/${uid}`).get(),
      db.doc(`users/${uid}/music/summary`).get(),
      db.doc(`users/${uid}/relationshipMatch/summary`).get(),
      db.collection(`users/${uid}/relationshipAnswers`).limit(120).get(),
    ]);

  const summaryAnswers = answersFromSummary(summarySnap.data());
  const answerCount = Math.max(
    Object.keys(summaryAnswers).length,
    answersSnap.size,
    Number(summarySnap.data()?.answerCount ?? 0),
  );

  const quality = profileQualityFromDocs({
    profile: profileSnap.data() ?? null,
    user: userSnap.data() ?? null,
    musicSummary: musicSnap.data() ?? null,
    personalityAnswerCount: answerCount,
    nowMs: Date.now(),
  });

  return {
    score: quality.score,
    factors: quality.factors,
    suggestions: quality.suggestions,
    personalityAnswerCount: answerCount,
    spotifyConnected:
      musicSnap.data()?.spotifyConnected === true ||
      profileSnap.data()?.spotifyConnected === true,
  };
});
