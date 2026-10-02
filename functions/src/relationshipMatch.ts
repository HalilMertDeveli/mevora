import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore, type DocumentData} from "firebase-admin/firestore";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {
  answersFromSummary,
  comparableAnswersFromSummary,
  isValidRelationshipAnswer,
  normalizeAnswerId,
  scoreRelationshipCompatibility,
  type RelationshipAnswers,
} from "./relationshipCompatibility.js";

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

function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "unauthenticated");
  }
  return uid;
}

/**
 * What the client needs about its own relationship answers. The timed test
 * offer (cooldowns, event counts, pauses) was retired with the matching
 * events; Relationship Learning (relationshipLearning/) replaced it.
 */
function snapshotPayload(answers: RelationshipAnswers) {
  return {
    answeredIds: Object.keys(answers).sort(),
    answerCount: Object.keys(answers).length,
  };
}

function profileQuestionAnswerRef(uid: string, questionId: string) {
  return db.doc(`users/${uid}/questionAnswers/${questionId}`);
}

function profileAnswerVisible(data?: DocumentData | null): boolean {
  return data?.isVisible !== false;
}

async function upsertProfileQuestionAnswer(input: {
  uid: string;
  questionId: string;
  answerId: string;
  existing?: DocumentData | null;
}): Promise<void> {
  const ref = profileQuestionAnswerRef(input.uid, input.questionId);
  const isVisible = profileAnswerVisible(input.existing);
  if (input.existing) {
    await ref.update({
      questionId: input.questionId,
      answerId: input.answerId,
      isVisible,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return;
  }
  await ref.set({
    questionId: input.questionId,
    answerId: input.answerId,
    isVisible: true,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
}

async function loadSummary(uid: string) {
  return db.doc(`users/${uid}/relationshipMatch/summary`).get();
}

async function loadAnswers(uid: string): Promise<RelationshipAnswers> {
  const summary = await loadSummary(uid);
  const fromSummary = answersFromSummary(summary.data());
  if (Object.keys(fromSummary).length > 0) {
    return fromSummary;
  }
  const snap = await db.collection(`users/${uid}/relationshipAnswers`).limit(120).get();
  const answers: RelationshipAnswers = {};
  for (const doc of snap.docs) {
    const answerId = doc.data().answerId;
    if (typeof answerId === "string" && isValidRelationshipAnswer(doc.id, answerId)) {
      answers[doc.id] = answerId;
    }
  }
  return answers;
}

export const saveRelationshipAnswer = onCall(
  callableOptions,
  async (request) => {
    try {
      const uid = requireUid(request);
      const questionId = String(request.data?.questionId ?? "");
      const answerId = normalizeAnswerId(request.data?.answerId) ?? String(request.data?.answerId ?? "");
      if (!isValidRelationshipAnswer(questionId, answerId)) {
        throw new HttpsError("invalid-argument", "invalid-relationship-answer");
      }
      const answerRef = db.doc(`users/${uid}/relationshipAnswers/${questionId}`);
      const summaryRef = db.doc(`users/${uid}/relationshipMatch/summary`);
      const profileRef = profileQuestionAnswerRef(uid, questionId);
      const current = await loadAnswers(uid);
      if (current[questionId] === answerId) {
        const profileSnap = await profileRef.get();
        if (!profileSnap.exists) {
          await upsertProfileQuestionAnswer({
            uid,
            questionId,
            answerId,
          });
        }
        return snapshotPayload(current);
      }
      current[questionId] = answerId;
      await db.runTransaction(async (tx) => {
        const existing = await tx.get(answerRef);
        const existingProfile = await tx.get(profileRef);
        if (existing.exists) {
          tx.update(answerRef, {
            answerId,
            answeredAt: FieldValue.serverTimestamp(),
          });
        } else {
          tx.create(answerRef, {
            questionId,
            answerId,
            answeredAt: FieldValue.serverTimestamp(),
          });
        }
        const profileVisible = existingProfile.exists
          ? profileAnswerVisible(existingProfile.data())
          : true;
        if (existingProfile.exists) {
          tx.update(profileRef, {
            questionId,
            answerId,
            isVisible: profileVisible,
            updatedAt: FieldValue.serverTimestamp(),
          });
        } else {
          tx.create(profileRef, {
            questionId,
            answerId,
            isVisible: true,
            createdAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          });
        }
        tx.set(
          summaryRef,
          {
            eligibleForMatching: Object.keys(current).length > 0,
            answerCount: Object.keys(current).length,
            answers: current,
            lastAnsweredAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        );
      });
      return snapshotPayload(current);
    } catch (error) {
      // A refusal this callable raised itself (bad input, signed out) is the
      // caller's answer, not an incident. Anything else is logged by its code
      // only: the message of a failed write can name the document, and the
      // answer a member gave is never written to a log.
      if (!(error instanceof HttpsError)) {
        logger.error("saveRelationshipAnswer failed", {
          uid: request.auth?.uid ?? null,
          code: (error as {code?: unknown})?.code ?? "unknown",
        });
      }
      throw error;
    }
  },
);

export const getRelationshipAnswered = onCall(
  callableOptions,
  async (request) => {
    const uid = requireUid(request);
    const answers = await loadAnswers(uid);
    return snapshotPayload(answers);
  },
);

export const syncProfileQuestionAnswers = onCall(
  callableOptions,
  async (request) => {
    const uid = requireUid(request);
    const answers = await loadAnswers(uid);
    const entries = Object.entries(answers);
    if (entries.length === 0) {
      return {synced: 0};
    }
    const batch = db.batch();
    for (const [questionId, answerId] of entries) {
      const ref = profileQuestionAnswerRef(uid, questionId);
      const existing = await ref.get();
      batch.set(
        ref,
        {
          questionId,
          answerId,
          isVisible: existing.exists ? profileAnswerVisible(existing.data()) : true,
          createdAt: existing.exists
            ? existing.data()?.createdAt ?? FieldValue.serverTimestamp()
            : FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    }
    await batch.commit();
    return {synced: entries.length};
  },
);

export const updateQuestionAnswerVisibility = onCall(
  callableOptions,
  async (request) => {
    const uid = requireUid(request);
    const questionId = String(request.data?.questionId ?? "");
    const isVisible = request.data?.isVisible === true;
    if (!/^rq_\d{3}$/.test(questionId)) {
      throw new HttpsError("invalid-argument", "invalid-question");
    }
    const ref = profileQuestionAnswerRef(uid, questionId);
    const snap = await ref.get();
    if (!snap.exists) {
      const answers = await loadAnswers(uid);
      const answerId = answers[questionId];
      if (!answerId) {
        throw new HttpsError("not-found", "answer-not-found");
      }
      await ref.set({
        questionId,
        answerId,
        isVisible,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {ok: true};
    }
    await ref.update({
      isVisible,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {ok: true};
  },
);

export async function relationshipScoreForPair(
  viewerUid: string,
  candidateUid: string,
): Promise<ReturnType<typeof scoreRelationshipCompatibility> | null> {
  const [viewer, candidate] = await Promise.all([
    db.doc(relationshipSummaryPath(viewerUid)).get(),
    db.doc(relationshipSummaryPath(candidateUid)).get(),
  ]);
  return relationshipScoreFromSummaries(viewerUid, candidateUid, viewer.data(), candidate.data());
}

export function relationshipSummaryPath(uid: string): string {
  return `users/${uid}/relationshipMatch/summary`;
}

/**
 * Whether a relationship summary carries comparable answers. Without them on
 * the viewer's side every pair score is null, so a pool scan need not read
 * any candidate's.
 */
export function hasRelationshipAnswers(summary: DocumentData | undefined): boolean {
  return Object.keys(comparableAnswersFromSummary(summary)).length > 0;
}

/**
 * The pair score from two summaries the caller already holds — for scans that
 * load the viewer's summary once and candidates' in bulk. No reads, and
 * nothing is logged: a pair's answers and how they compare are private to the
 * two members. The uids are part of the signature for the callers only.
 */
export function relationshipScoreFromSummaries(
  viewerUid: string,
  candidateUid: string,
  viewerSummary: DocumentData | undefined,
  candidateSummary: DocumentData | undefined,
): ReturnType<typeof scoreRelationshipCompatibility> | null {
  const viewerAnswers = comparableAnswersFromSummary(viewerSummary);
  const candidateAnswers = comparableAnswersFromSummary(candidateSummary);
  if (Object.keys(viewerAnswers).length === 0 || Object.keys(candidateAnswers).length === 0) {
    return null;
  }
  const viewerKey = viewerSummary?.compatibilityKey;
  const candidateKey = candidateSummary?.compatibilityKey;
  const rel = scoreRelationshipCompatibility(viewerAnswers, candidateAnswers);
  const keyMatch =
    typeof viewerKey === "string" &&
    typeof candidateKey === "string" &&
    viewerKey.length > 0 &&
    viewerKey === candidateKey;
  const alignedForRank = keyMatch
    ? Math.max(rel.alignedCount, 3)
    : rel.alignedCount;
  if (alignedForRank <= 0) {
    return null;
  }
  return {
    score: keyMatch ? 100 : rel.score,
    sharedQuestionCount: keyMatch ? Math.max(rel.sharedQuestionCount, 3) : rel.sharedQuestionCount,
    alignedCount: alignedForRank,
    topTopics: rel.topTopics,
  };
}
