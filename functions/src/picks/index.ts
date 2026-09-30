import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {isAccountEligible} from "../profileSafety.js";
import {loadDiscoveryViewerBasics} from "../discoveryPool.js";
import {isLearningBlockingPicks, learningSummary} from "../relationshipLearning/model.js";
import {learningDayKey} from "../relationshipLearning/schedule.js";
import {loadLearningState} from "../relationshipLearning/store.js";
import {servePicks} from "./service.js";
import {assertAppFeatureAvailable} from "../appOperations/appOperationsGate.js";
import {logger} from "firebase-functions";
import {meterReads} from "./readMeter.js";
import type {PicksCostPath} from "./service.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";

/**
 * Mevora Picks for the signed-in member.
 *
 * Cost is bounded by the batch lifecycle rather than a request quota: a pool
 * scan happens only when a batch is generated (once per member per day) or a
 * Pick that became ineligible is replaced. Every other call reads the stored
 * batch and revalidates only the handful of Picks still active in it — its
 * cost does not grow with the member's history.
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
    // Every billed read this open makes, kept apart by what the open did:
    // a day's generation, a same-day reopen, a wait for another open's
    // generation, a replacement scan, or an early empty answer.
    const trace: {path: PicksCostPath} = {path: "empty"};
    const startedAt = Date.now();
    const {result, tally} = await meterReads(() => openPicks(uid, trace));
    logger.info("mevora_picks_cost", {
      path: trace.path,
      reads: tally?.reads ?? null,
      documents: tally?.documents ?? null,
      queries: tally?.queries ?? null,
      queryDocuments: tally?.queryDocuments ?? null,
      picks: Array.isArray(result.picks) ? result.picks.length : 0,
      targetCount: result.targetCount ?? null,
      durationMs: Date.now() - startedAt,
    });
    return result;
  },
);

async function openPicks(uid: string, trace: {path: PicksCostPath}): Promise<Record<string, unknown>> {
  const callerAccount = await db.doc(`users/${uid}`).get();
  if (!isAccountEligible(callerAccount.data())) {
    throw new HttpsError("permission-denied", "account-suspended");
  }
  await assertAppFeatureAvailable(db, "picks");
  const nowMs = Date.now();
  const learningState = await loadLearningState(db, uid);
  const learning = learningSummary(learningState, learningDayKey(nowMs), nowMs);
  if (isLearningBlockingPicks(learningState)) {
    // A new member's first Picks wait for their first daily question set:
    // the set is chosen from their answers, so it is not served without them.
    return {status: "empty", emptyReason: "learningRequired", picks: [], learning};
  }
  // Only what does not grow with history or with the size of Mevora is
  // read. Decisions, blocks and live Boosts are looked up for the specific
  // people being checked — never as the member's whole history, never as
  // every Boost in the system.
  const viewer = await loadDiscoveryViewerBasics(db, uid, callerAccount.data());
  if (viewer.prefs.discoveryEnabled === false) {
    // A member who turned discovery off is not shown to anyone, and is not
    // shown anyone either.
    return {status: "empty", emptyReason: "discoveryDisabled", picks: [], learning};
  }
  return {...(await servePicks({db, viewer, nowMs, trace})), learning};
}

