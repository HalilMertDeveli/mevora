import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {isAccountEligible} from "../profileSafety.js";
import {INITIAL_QUESTION_COUNT, LEARNING_CATALOG_VERSION, initialQuestions, learningQuestion} from "./catalog.js";
import {PROGRESSIVE} from "./config.js";
import {
  answerHighlights,
  answeredQuestionIds,
  categoryProgress,
  learningCategoryOf,
  overallProgress,
} from "./overview.js";
import {
  applyAnswer,
  declaredConfidence,
  ensureProgressiveBatch,
  initialAnsweredCount,
  isInitialComplete,
  isProgressivePromptDue,
  learningSummary,
  type LearningState,
  type ProfileSignals,
  parseLearningState,
  emptyLearningState,
} from "./model.js";
import {
  learningMirrorWrite,
  learningStatePath,
  learningStateWrite,
  loadProfileSignals,
  questionPayload,
  relationshipSummaryPath,
} from "./store.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const REGION = "europe-west1" as const;
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";

function requireUid(uid: string | undefined): string {
  if (!uid) throw new HttpsError("unauthenticated", "sign-in-required");
  return uid;
}

async function requireEligible(uid: string): Promise<void> {
  const account = await db.doc(`users/${uid}`).get();
  if (!isAccountEligible(account.data())) {
    throw new HttpsError("permission-denied", "account-suspended");
  }
}

/**
 * Everything the relationship-learning screens need: the initial questions
 * with the member's saved answers (so a restart resumes where they left off),
 * and the current follow-up round. Creates the next round when there is none,
 * so what the member sees stays the same until they answer it.
 */
export const getRelationshipLearningState = onCall(
  {enforceAppCheck, region: REGION},
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    await requireEligible(uid);
    const nowMs = Date.now();
    const ref = db.doc(learningStatePath(uid));
    const signals = await loadProfileSignals(db, uid);

    const state = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const current = snap.exists ? parseLearningState(snap.data()) : emptyLearningState();
      const confidence = declaredConfidence(current, signals);
      const {state: next, created} = ensureProgressiveBatch(current, confidence, nowMs);
      if (created) tx.set(ref, learningStateWrite(next), {merge: true});
      return next;
    });

    const initial = initialQuestions();
    const round = state.progressive.batch
      .map((id) => learningQuestion(id))
      .filter((question) => question !== null);
    return {
      catalogVersion: LEARNING_CATALOG_VERSION,
      ...learningSummary(state, nowMs, {humorCalibrated: signals.humorReady}),
      initial: {
        total: INITIAL_QUESTION_COUNT,
        answered: initialAnsweredCount(state),
        completed: isInitialComplete(state),
        questions: initial.map((question) => questionPayload(question, state)),
      },
      progressive: {
        due: isProgressivePromptDue(state, nowMs),
        batchSize: PROGRESSIVE.batchSize,
        questions: round.map((question) => questionPayload(question, state)),
      },
      overview: overviewPayload(state, signals),
    };
  },
);

/** The learning dashboard: real coverage, the member's own read-backs, and their answers. */
function overviewPayload(state: LearningState, signals: ProfileSignals): Record<string, unknown> {
  const categories = categoryProgress(state, signals);
  return {
    overallProgress: overallProgress(categories),
    categories,
    highlights: answerHighlights(state),
    answered: answeredQuestionIds(state)
      .map((id) => learningQuestion(id))
      .filter((question) => question !== null)
      .map((question) => ({
        ...questionPayload(question, state),
        category: learningCategoryOf(question),
        answeredAtMs: state.answers[question.id]?.answeredAtMs ?? null,
      })),
  };
}

/**
 * "Skip for now" on the onboarding Humor Lab step. Recorded on the server so
 * the journey moves on to Relationship Learning and never loops back; the
 * Humor Lab itself stays available. Idempotent: the first skip time is kept.
 */
export const skipOnboardingHumor = onCall(
  {enforceAppCheck, region: REGION},
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    const nowMs = Date.now();
    const ref = db.doc(learningStatePath(uid));
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return; // Existing members have no journey to advance.
      const state = parseLearningState(snap.data());
      if (state.journey.humorSkippedAtMs !== null) return;
      tx.set(ref, learningStateWrite({...state, journey: {humorSkippedAtMs: nowMs}}), {merge: true});
    });
    return {ok: true};
  },
);

/**
 * Saves one answer, exactly once. Validates the question and the option
 * against the server catalog; re-sending the same answer is a no-op, so a
 * retried request, a double tap or a resumed session cannot duplicate
 * anything or complete the initial set twice.
 */
export const saveRelationshipLearningAnswer = onCall(
  {enforceAppCheck, region: REGION},
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const questionId = data.questionId;
    const answerId = data.answerId;
    if (!learningQuestion(questionId)) {
      throw new HttpsError("invalid-argument", "invalid-question");
    }
    await requireEligible(uid);
    const nowMs = Date.now();
    const stateRef = db.doc(learningStatePath(uid));
    const summaryRef = db.doc(relationshipSummaryPath(uid));

    const result = await db.runTransaction(async (tx) => {
      const snap = await tx.get(stateRef);
      const current = snap.exists ? parseLearningState(snap.data()) : emptyLearningState();
      const outcome = applyAnswer(current, questionId, answerId, nowMs);
      if (!outcome.ok) return outcome;
      if (outcome.changed) {
        tx.set(stateRef, {
          ...learningStateWrite(outcome.state),
          ...(snap.exists ? {} : {createdAt: FieldValue.serverTimestamp()}),
        }, {merge: true});
        // Answer maps only ever gain keys or change values, so a merge write
        // can never leave a stale answer behind.
        tx.set(summaryRef, learningMirrorWrite(outcome.state), {merge: true});
      }
      return outcome;
    });

    if (!result.ok) {
      const code = result.reason === "rate-limited" ? "resource-exhausted" : "invalid-argument";
      throw new HttpsError(code, result.reason);
    }
    if (result.completedInitialNow) {
      logger.info("relationshipLearning: initial set completed", {catalogVersion: LEARNING_CATALOG_VERSION});
    }
    return {
      ok: true,
      changed: result.changed,
      completedInitialNow: result.completedInitialNow,
      completedRoundNow: result.completedBatchNow,
      ...learningSummary(result.state, nowMs),
    };
  },
);

/** "Not now" for the follow-up round: hides the invitation for a while. */
export const snoozeRelationshipLearningPrompt = onCall(
  {enforceAppCheck, region: REGION},
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    const nowMs = Date.now();
    const ref = db.doc(learningStatePath(uid));
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return;
      const state = parseLearningState(snap.data());
      tx.set(ref, learningStateWrite({
        ...state,
        progressive: {...state.progressive, snoozedUntilMs: nowMs + PROGRESSIVE.snoozeMs},
      }), {merge: true});
    });
    return {ok: true, snoozedUntilMs: nowMs + PROGRESSIVE.snoozeMs};
  },
);
