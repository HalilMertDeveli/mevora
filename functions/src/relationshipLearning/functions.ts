import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {isAccountEligible} from "../profileSafety.js";
import {LEARNING_CATALOG_VERSION, learningQuestion} from "./catalog.js";
import {
  answerHighlights,
  answerTotals,
  answeredQuestionIds,
  categoryProgress,
  overallProgress,
} from "./overview.js";
import {
  applyDailyAnswer,
  emptyLearningState,
  learningSummary,
  parseLearningState,
  skipToday,
  updateEarlierAnswer,
  type LearningState,
  type ProfileSignals,
} from "./model.js";
import {coreProgress, memberDailySet} from "./schedule.js";
import {
  dailyCompletionPath,
  dailySetPayload,
  learningStatePath,
  loadProfileSignals,
  questionPayload,
  relationshipSummaryPath,
  resolveLearningDayKey,
  writeLearningMirror,
  writeLearningState,
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
 * The member's question set for today with the answers given so far (so a
 * restart resumes on the first unanswered question), the progress summary,
 * their place in the Core sequence and the dashboard. The day is the SERVER's
 * logical day and the set follows from the member's own answers; nothing the
 * client sends can choose another day or another set.
 */
export const getRelationshipLearningState = onCall(
  {enforceAppCheck, region: REGION},
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    await requireEligible(uid);
    const nowMs = Date.now();
    const [dateKey, stateSnap, signals] = await Promise.all([
      resolveLearningDayKey(db, nowMs),
      db.doc(learningStatePath(uid)).get(),
      loadProfileSignals(db, uid),
    ]);
    const state = stateSnap.exists ? parseLearningState(stateSnap.data()) : emptyLearningState();
    const set = memberDailySet(state, dateKey);
    const summary = learningSummary(state, set, nowMs, {humorCalibrated: signals.humorReady});
    return {
      catalogVersion: LEARNING_CATALOG_VERSION,
      ...summary,
      today: {
        ...(summary.today as Record<string, unknown>),
        questions: dailySetPayload(set, state),
      },
      core: coreProgress(state),
      overview: overviewPayload(state, signals, dateKey),
    };
  },
);

/** The learning dashboard: real coverage and counts, the member's own read-backs, and their answers. */
function overviewPayload(state: LearningState, signals: ProfileSignals, dateKey: string): Record<string, unknown> {
  const categories = categoryProgress(state, signals);
  return {
    overallProgress: overallProgress(categories),
    categories,
    totals: answerTotals(state, dateKey),
    highlights: answerHighlights(state),
    answered: answeredQuestionIds(state)
      .map((id) => learningQuestion(id))
      .filter((question) => question !== null)
      .map((question) => ({
        ...questionPayload(question, state.answers[question.id]?.answerId ?? null),
        answeredAtMs: state.answers[question.id]?.answeredAtMs ?? null,
      })),
  };
}

function rejection(reason: string): HttpsError {
  return new HttpsError(reason === "rate-limited" ? "resource-exhausted" : "invalid-argument", reason);
}

/**
 * Saves one answer to the member's set for TODAY, exactly once. The set id,
 * question id, question version and option are all checked against the set
 * the server derives for the server's day, inside the same transaction that
 * writes the answer. Re-sending the same answer is a no-op, so a retry, a
 * double tap or a resumed session cannot duplicate an answer, a count or a
 * completion.
 */
export const saveDailyRelationshipAnswer = onCall(
  {enforceAppCheck, region: REGION},
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    const data = (request.data ?? {}) as Record<string, unknown>;
    if (typeof data.questionSetId !== "string" || !learningQuestion(data.questionId)) {
      throw new HttpsError("invalid-argument", "invalid-question");
    }
    await requireEligible(uid);
    const nowMs = Date.now();
    const dateKey = await resolveLearningDayKey(db, nowMs);
    const stateRef = db.doc(learningStatePath(uid));
    const summaryRef = db.doc(relationshipSummaryPath(uid));

    const {outcome: result, set} = await db.runTransaction(async (tx) => {
      const [snap, summarySnap] = await Promise.all([tx.get(stateRef), tx.get(summaryRef)]);
      const current = snap.exists ? parseLearningState(snap.data()) : emptyLearningState();
      const set = memberDailySet(current, dateKey);
      const outcome = applyDailyAnswer(current, set, {
        questionSetId: data.questionSetId,
        questionId: data.questionId,
        questionVersion: data.questionVersion,
        answerId: data.answerId,
      }, nowMs);
      if (!outcome.ok || !outcome.changed) return {outcome, set};
      writeLearningState(tx, db, uid, outcome.state, snap.data());
      writeLearningMirror(tx, db, uid, outcome.state, summarySnap.exists);
      if (outcome.completedTodayNow) {
        tx.set(db.doc(dailyCompletionPath(uid, dateKey)), {
          dateKey,
          questionSetId: set.questionSetId,
          kind: set.kind,
          questionCount: set.questions.length,
          firstSet: outcome.firstSetCompletedNow,
          completedAt: FieldValue.serverTimestamp(),
        });
      }
      return {outcome, set};
    });

    if (!result.ok) throw rejection(result.reason);
    if (result.completedTodayNow) {
      logger.info("relationshipLearning: daily set completed", {
        questionSetId: set.questionSetId,
        kind: set.kind,
        firstSet: result.firstSetCompletedNow,
      });
    }
    return {
      ok: true,
      changed: result.changed,
      completedTodayNow: result.completedTodayNow,
      firstSetCompletedNow: result.firstSetCompletedNow,
      ...learningSummary(result.state, memberDailySet(result.state, dateKey), nowMs),
    };
  },
);

/**
 * Changes an answer the member gave on an earlier day (or earlier today),
 * from the dashboard. Only already-answered questions in their current
 * version; it never answers anything new.
 */
export const updateRelationshipAnswer = onCall(
  {enforceAppCheck, region: REGION},
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    const data = (request.data ?? {}) as Record<string, unknown>;
    if (!learningQuestion(data.questionId)) {
      throw new HttpsError("invalid-argument", "invalid-question");
    }
    await requireEligible(uid);
    const nowMs = Date.now();
    const stateRef = db.doc(learningStatePath(uid));
    const summaryRef = db.doc(relationshipSummaryPath(uid));

    const result = await db.runTransaction(async (tx) => {
      const [snap, summarySnap] = await Promise.all([tx.get(stateRef), tx.get(summaryRef)]);
      if (!snap.exists) return {ok: false as const, reason: "not-answered" as const};
      const outcome = updateEarlierAnswer(parseLearningState(snap.data()), {
        questionId: data.questionId,
        questionVersion: data.questionVersion,
        answerId: data.answerId,
      }, nowMs);
      if (!outcome.ok || !outcome.changed) return outcome;
      writeLearningState(tx, db, uid, outcome.state, snap.data());
      writeLearningMirror(tx, db, uid, outcome.state, summarySnap.exists);
      return outcome;
    });

    if (!result.ok) throw rejection(result.reason);
    return {ok: true, changed: result.changed};
  },
);

/**
 * "Bugünlük geç": hides today's set until the next logical day. A new
 * member's onboarding questions cannot be skipped. Idempotent.
 */
export const skipTodayRelationshipQuestions = onCall(
  {enforceAppCheck, region: REGION},
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    await requireEligible(uid);
    const nowMs = Date.now();
    const dateKey = await resolveLearningDayKey(db, nowMs);
    const ref = db.doc(learningStatePath(uid));
    const result = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const current = snap.exists ? parseLearningState(snap.data()) : emptyLearningState();
      const outcome = skipToday(current, memberDailySet(current, dateKey), nowMs);
      if (outcome.ok && outcome.state !== current) {
        writeLearningState(tx, db, uid, outcome.state, snap.data());
      }
      return outcome;
    });
    if (!result.ok) throw new HttpsError("failed-precondition", result.reason);
    return {ok: true, ...learningSummary(result.state, memberDailySet(result.state, dateKey), nowMs)};
  },
);

/**
 * "Skip for now" on the onboarding Humor Lab step. Recorded on the server so
 * the journey moves on to today's questions and never loops back; the Humor
 * Lab itself stays available. Idempotent: the first skip time is kept.
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
      writeLearningState(tx, db, uid, {...state, journey: {humorSkippedAtMs: nowMs}}, snap.data());
    });
    return {ok: true};
  },
);
