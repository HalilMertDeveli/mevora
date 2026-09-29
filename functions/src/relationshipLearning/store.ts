import {FieldValue, type DocumentData, type Firestore} from "firebase-admin/firestore";
import {isHumorCalibrationReady} from "../humor/compatibility.js";
import {answersFromSummary} from "../relationshipCompatibility.js";
import {LEARNING_CATALOG_VERSION, type LearningQuestion} from "./catalog.js";
import {
  comparableAnswers,
  emptyLearningState,
  parseLearningState,
  serializeLearningState,
  type LearningState,
  type ProfileSignals,
} from "./model.js";

/**
 * Firestore side of Relationship Learning.
 *
 *   users/{uid}/relationshipLearning/state   answers, progress, rounds (server-only; owner may read)
 *   users/{uid}/relationshipMatch/summary    .learningAnswers — stance answers mirrored for the
 *                                            pair scorer, so scoring costs no extra read
 *
 * Every write goes through a callable; the client can never write either
 * document, so answers are validated and derived state cannot be forged.
 */

export function learningStatePath(uid: string): string {
  return `users/${uid}/relationshipLearning/state`;
}

export function relationshipSummaryPath(uid: string): string {
  return `users/${uid}/relationshipMatch/summary`;
}

export async function loadLearningState(db: Firestore, uid: string): Promise<LearningState> {
  const snap = await db.doc(learningStatePath(uid)).get();
  return snap.exists ? parseLearningState(snap.data()) : emptyLearningState();
}

/** The learning-state document body, with a server timestamp. */
export function learningStateWrite(state: LearningState): Record<string, unknown> {
  return {
    ...serializeLearningState(state),
    catalogVersion: LEARNING_CATALOG_VERSION,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/** The summary mirror: replaces the whole map so a changed answer never lingers. */
export function learningMirrorWrite(state: LearningState): Record<string, unknown> {
  return {
    learningAnswers: comparableAnswers(state),
    learningUpdatedAt: FieldValue.serverTimestamp(),
  };
}

function hasText(value: unknown): boolean {
  return String(value ?? "").trim().length > 0;
}

function hasList(value: unknown, min = 1): boolean {
  return Array.isArray(value) && value.filter((item) => hasText(item)).length >= min;
}

function hasLifestyle(data: DocumentData): boolean {
  if (hasList(data.lifestyle)) return true;
  const profile = data.lifestyleProfile as Record<string, unknown> | undefined;
  return !!profile && Object.values(profile).some((value) => hasText(value));
}

/** What the member's existing profile already says, reused for confidence. */
export async function loadProfileSignals(db: Firestore, uid: string): Promise<ProfileSignals> {
  const [profile, summary, music, calibration] = await Promise.all([
    db.doc(`profiles/${uid}`).get(),
    db.doc(relationshipSummaryPath(uid)).get(),
    db.doc(`users/${uid}/music/summary`).get(),
    db.doc(`users/${uid}/humor/calibration`).get(),
  ]);
  const data = profile.data() ?? {};
  return {
    hasRelationshipGoal: hasText(data.relationshipGoal),
    hasLifestyle: hasLifestyle(data),
    hasInterests: hasList(data.interests, 3),
    hasMusic: music.exists,
    humorReady: calibration.exists && isHumorCalibrationReady(calibration.data(), null),
    relationshipAnswerCount: Object.keys(answersFromSummary(summary.data())).length,
  };
}

/**
 * Marks a member who just finished onboarding as someone whose daily Picks
 * wait for the initial questions. Create-only: it never touches a member who
 * already has state, and a failure leaves them unblocked rather than stuck.
 */
export async function markLearningRequired(db: Firestore, uid: string): Promise<void> {
  const ref = db.doc(learningStatePath(uid));
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists) return;
    const state = {...emptyLearningState(), required: true};
    tx.set(ref, {...learningStateWrite(state), createdAt: FieldValue.serverTimestamp()});
  });
}

// ---------------------------------------------------------------------------
// Client payloads. Copy for both languages; no scoring metadata.
// ---------------------------------------------------------------------------

export interface QuestionPayload {
  id: string;
  version: number;
  kind: string;
  dimension: string;
  prompt: {tr: string; en: string};
  options: Array<{id: string; label: {tr: string; en: string}}>;
  answerId: string | null;
}

export function questionPayload(question: LearningQuestion, state: LearningState): QuestionPayload {
  return {
    id: question.id,
    version: question.version,
    kind: question.kind,
    dimension: question.dimension,
    prompt: {...question.prompt},
    options: question.options.map((option) => ({id: option.id, label: {...option.label}})),
    answerId: state.answers[question.id]?.answerId ?? null,
  };
}
