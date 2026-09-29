import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {onDocumentCreated, onDocumentWritten} from "firebase-functions/v2/firestore";
import {PERSONALIZATION_ALGORITHM_VERSION, SIGNAL_STRENGTHS} from "./config.js";
import {effectiveAdjustments} from "./learner.js";
import {explainPersonalRanking, isPersonalizationActive} from "./ranking.js";
import {engagementStrength, parseProfileEngagement, utcDayKey} from "./signals.js";
import {
  loadPersonalizationContext,
  pairScores,
  recordLearningEventSafely,
  resetLearnedPersonalization,
} from "./store.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const REGION = "europe-west1" as const;
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";

const LIKE_ACTIONS = {
  like: "like",
  superLike: "superLike",
  pass: "pass",
} as const satisfies Record<string, keyof typeof SIGNAL_STRENGTHS>;

function isUid(value: unknown): value is string {
  return typeof value === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value);
}

/**
 * Like / Super Like / Pass. Driven by the canonical `likes/{from}_{to}` write
 * both decision callables make, so no screen had to be instrumented and a
 * client cannot fabricate one. A rewrite with the same action is not a new
 * decision; a changed action (pass, then later like) is.
 */
export const personalizationOnDecision = onDocumentWritten(
  {document: "likes/{likeId}", region: REGION},
  async (event) => {
    const after = event.data?.after.data();
    if (!after) return;
    const before = event.data?.before.data();
    const action = String(after.action ?? "") as keyof typeof LIKE_ACTIONS;
    const type = LIKE_ACTIONS[action];
    if (!type || before?.action === after.action) return;
    const actorUid = after.fromUserId;
    const otherUid = after.toUserId;
    if (!isUid(actorUid) || !isUid(otherUid) || actorUid === otherUid) return;
    await recordLearningEventSafely(db, {
      actorUid,
      otherUid,
      type,
      key: "decision",
      strength: SIGNAL_STRENGTHS[type],
    });
  },
);

/** Match: a positive outcome for both people. */
export const personalizationOnMatchCreated = onDocumentCreated(
  {document: "matches/{matchId}", region: REGION},
  async (event) => {
    const data = event.data?.data();
    const userIds = ((data?.userIds as unknown[]) ?? []).filter(isUid);
    if (userIds.length !== 2 || data?.isActive === false) return;
    const [a, b] = userIds;
    await Promise.all([
      recordLearningEventSafely(db, {
        actorUid: a, otherUid: b, type: "match", key: event.params.matchId,
        strength: SIGNAL_STRENGTHS.match,
      }),
      recordLearningEventSafely(db, {
        actorUid: b, otherUid: a, type: "match", key: event.params.matchId,
        strength: SIGNAL_STRENGTHS.match,
      }),
    ]);
  },
);

/**
 * Weak profile engagement: one aggregated report per profile visit. The
 * client sends only booleans, a photo count and foreground dwell; the server
 * clamps, buckets and caps them, and counts at most one per candidate per day.
 */
export const recordProfileEngagement = onCall(
  {enforceAppCheck, region: REGION},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "sign-in-required");
    const data = (request.data ?? {}) as Record<string, unknown>;
    const candidateUid = data.candidateUid;
    if (!isUid(candidateUid) || candidateUid === uid) {
      throw new HttpsError("invalid-argument", "invalid-candidate");
    }
    const strength = engagementStrength(parseProfileEngagement(data));
    if (strength <= 0) return {ok: true, outcome: "ignored"};
    const outcome = await recordLearningEventSafely(db, {
      actorUid: uid,
      otherUid: candidateUid,
      type: "profileEngagement",
      key: utcDayKey(Date.now()),
      strength,
      weak: true,
    });
    return {ok: true, outcome};
  },
);

/**
 * "Reset what Mevora learned from me". Clears the observed profile only; the
 * member's declared answers and their switch are untouched. The client can
 * never write learned state itself, so this callable is the only way to it.
 */
export const resetMyPersonalization = onCall(
  {enforceAppCheck, region: REGION},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "sign-in-required");
    const removed = await resetLearnedPersonalization(db, uid);
    logger.info("personalization: learned profile reset", {removed});
    return {ok: true};
  },
);

/**
 * Development/QA only: how the caller's personalization would rank the given
 * candidates. Refuses outside the emulator so no production member can read
 * raw scoring internals about anyone.
 */
export const debugPersonalizationRanking = onCall(
  {enforceAppCheck, region: REGION},
  async (request) => {
    if (process.env.FUNCTIONS_EMULATOR !== "true") {
      throw new HttpsError("failed-precondition", "emulator-only");
    }
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "sign-in-required");
    const requested = Array.isArray(request.data?.candidateUids)
      ? (request.data.candidateUids as unknown[]).filter(isUid).slice(0, 20)
      : [];
    const context = await loadPersonalizationContext(db, uid);
    const learned = effectiveAdjustments(context.profile, true);
    const candidates = await Promise.all(
      requested.map(async (candidateUid) => {
        const scores = await pairScores(db, uid, candidateUid);
        if (!scores) return {uid: candidateUid, available: false};
        return {
          uid: candidateUid,
          available: true,
          vector: scores.vector,
          explanation: explainPersonalRanking(scores.overall, scores.vector, context.adjustments),
        };
      }),
    );
    return {
      algorithmVersion: PERSONALIZATION_ALGORITHM_VERSION,
      enabled: context.enabled,
      active: isPersonalizationActive(context.adjustments),
      learnedAdjustments: learned,
      declaredAdjustments: context.declared,
      observedAdjustments: context.observed,
      effectiveAdjustments: context.adjustments,
      partnerCount: context.profile.partnerCount,
      eventCount: context.profile.eventCount,
      dimensions: context.profile.dimensions,
      candidates,
    };
  },
);
