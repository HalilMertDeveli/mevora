import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore, type DocumentData} from "firebase-admin/firestore";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
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

function relDebug(message: string, extra?: unknown): void {
  if (extra === undefined) {
    console.log(`[RELATIONSHIP_DEBUG] ${message}`);
    return;
  }
  console.log(`[RELATIONSHIP_DEBUG] ${message}`, extra);
}

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
      relDebug(`Question answers submitted ${questionId}=${answerId}`);
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
        relDebug("Answer unchanged");
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
      relDebug("Answers saved successfully");
      return snapshotPayload(current);
    } catch (error) {
      const err = error as {code?: string; message?: string};
      relDebug(
        `FirebaseException ${err.code ?? "unknown"}: ${err.message ?? String(error)}`,
      );
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
    relDebug(`Profile question answers synced: ${entries.length}`);
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
 * load the viewer's summary once and candidates' in bulk. No reads.
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
  const questionIds = Array.isArray(viewerSummary?.questionIds)
    ? (viewerSummary?.questionIds as unknown[]).map((id) => String(id))
    : Object.keys(viewerAnswers).slice(0, 3);
  const rel = scoreRelationshipCompatibility(viewerAnswers, candidateAnswers);
  const keyMatch =
    typeof viewerKey === "string" &&
    typeof candidateKey === "string" &&
    viewerKey.length > 0 &&
    viewerKey === candidateKey;
  if (keyMatch) {
    relDebug(
      `User ${viewerUid} vs ${candidateUid}: exact compatibilityKey → treat as 3/3 session match`,
    );
  }
  const debugIds =
    questionIds.length === 3 ? questionIds : Object.keys(viewerAnswers).filter((id) => candidateAnswers[id] != null).slice(0, 3);
  for (const questionId of debugIds) {
    const match =
      (normalizeAnswerId(viewerAnswers[questionId]) ?? viewerAnswers[questionId]) ===
      (normalizeAnswerId(candidateAnswers[questionId]) ?? candidateAnswers[questionId]);
    relDebug(
      `User ${viewerUid} vs ${candidateUid} ${questionId}: ${match ? "MATCH" : "NO MATCH"} ` +
        `(${viewerAnswers[questionId]} vs ${candidateAnswers[questionId]})`,
    );
  }
  const alignedForRank = keyMatch
    ? Math.max(rel.alignedCount, 3)
    : rel.alignedCount;
  relDebug(
    `User ${viewerUid} vs ${candidateUid}: ${alignedForRank}/${rel.sharedQuestionCount} ` +
      `score=${keyMatch ? 100 : rel.score}% FINAL PRIORITY: ${
        alignedForRank >= 3 ? "VERY HIGH" : alignedForRank === 2 ? "HIGH" : alignedForRank === 1 ? "MEDIUM" : "LOW"
      }`,
  );
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
