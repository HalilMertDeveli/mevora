import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {isAccountEligible} from "../profileSafety.js";
import {loadDiscoveryViewerContext} from "../discoveryPool.js";
import {isLearningBlockingPicks, learningSummary} from "../relationshipLearning/model.js";
import {loadLearningState} from "../relationshipLearning/store.js";
import {servePicks} from "./service.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";

/**
 * Mevora Picks for the signed-in member.
 *
 * Cost is bounded by the batch lifecycle rather than a request quota: a pool
 * scan happens only when a batch is generated (at most once per batch TTL) or
 * topped up (at most once per `topUpMinIntervalMs`). Every other call only
 * revalidates the handful of Picks already chosen.
 *
 * Ranking, categories and reasons are computed here and nowhere else; the
 * client renders what it receives and never sends a score.
 */
export const getMevoraPicks = onCall(
  {enforceAppCheck, region: "europe-west1"},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const callerAccount = await db.doc(`users/${uid}`).get();
    if (!isAccountEligible(callerAccount.data())) {
      throw new HttpsError("permission-denied", "account-suspended");
    }
    const nowMs = Date.now();
    const learningState = await loadLearningState(db, uid);
    const learning = learningSummary(learningState, nowMs);
    if (isLearningBlockingPicks(learningState)) {
      // A new member's first Picks wait for the initial questions: the set
      // is chosen from their answers, so it is not served without them.
      return {status: "empty", emptyReason: "learningRequired", picks: [], learning};
    }
    const {viewer, boostSessions} = await loadDiscoveryViewerContext(db, uid, callerAccount.data());
    if (viewer.prefs.discoveryEnabled === false) {
      // Same switch that empties Discover: a member who turned discovery off
      // is not shown to anyone, and is not shown anyone either.
      return {status: "empty", emptyReason: "discoveryDisabled", picks: [], learning};
    }
    return {...(await servePicks({db, viewer, boostSessions, nowMs})), learning};
  },
);
