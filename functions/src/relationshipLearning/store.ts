import {FieldValue, type DocumentData, type Firestore, type Transaction} from "firebase-admin/firestore";
import {isHumorCalibrationReady} from "../humor/compatibility.js";
import {answersFromSummary} from "../relationshipCompatibility.js";
import {LEARNING_CATALOG_VERSION, learningQuestion, type LearningQuestion} from "./catalog.js";
import {
  comparableAnswers,
  emptyLearningState,
  parseLearningState,
  serializeLearningState,
  type LearningState,
  type ProfileSignals,
} from "./model.js";
import {isDateKey, learningDayKey, type DailySet} from "./schedule.js";

/**
 * Firestore side of the relationship questions.
 *
 *   users/{uid}/relationshipLearning/state        answers, today's frozen set and progress
 *                                                 (server-only; owner may read)
 *   users/{uid}/relationshipDaily/{dateKey}       one record per completed day (server-only; owner may read)
 *   users/{uid}/relationshipMatch/summary         .learningAnswers — comparable answers mirrored for
 *                                                 the pair scorer, so scoring costs no extra read
 *
 * Every member write goes through a callable, so answers are validated and
 * derived state cannot be forged.
 */

export function learningStatePath(uid: string): string {
  return `users/${uid}/relationshipLearning/state`;
}

export function dailyCompletionPath(uid: string, dateKey: string): string {
  return `users/${uid}/relationshipDaily/${dateKey}`;
}

export function relationshipSummaryPath(uid: string): string {
  return `users/${uid}/relationshipMatch/summary`;
}

/**
 * Emulator-only clock override: `devClock/relationshipLearning {dateKey}`.
 * Read only when the process runs inside the Functions emulator, so a
 * deployed function can never be steered to another day. Clients cannot
 * write it (rules deny). Moved with tool/relationshipLearningDev.cjs.
 */
export const LEARNING_DEV_CLOCK_DOC = "devClock/relationshipLearning";

/** Today's logical day. Server clock; the override applies in the emulator only. */
export async function resolveLearningDayKey(db: Firestore, nowMs: number): Promise<string> {
  if (process.env.FUNCTIONS_EMULATOR === "true") {
    const override = (await db.doc(LEARNING_DEV_CLOCK_DOC).get()).data()?.dateKey;
    if (isDateKey(override)) return override;
  }
  return learningDayKey(nowMs);
}

export async function loadLearningState(db: Firestore, uid: string): Promise<LearningState> {
  const snap = await db.doc(learningStatePath(uid)).get();
  return snap.exists ? parseLearningState(snap.data()) : emptyLearningState();
}

/**
 * Writes the whole state (not a merge): maps like today's progress must never
 * keep keys from an earlier shape. `createdAt` is carried over.
 */
export function writeLearningState(
  tx: Transaction,
  db: Firestore,
  uid: string,
  state: LearningState,
  existing: DocumentData | undefined,
): void {
  tx.set(db.doc(learningStatePath(uid)), {
    ...serializeLearningState(state),
    catalogVersion: LEARNING_CATALOG_VERSION,
    createdAt: existing?.createdAt ?? FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
}

/**
 * Replaces the comparable-answer mirror wholesale (update, not merge), so an
 * answer to a retired question or version never lingers in pair scoring.
 */
export function writeLearningMirror(
  tx: Transaction,
  db: Firestore,
  uid: string,
  state: LearningState,
  summaryExists: boolean,
): void {
  const ref = db.doc(relationshipSummaryPath(uid));
  const fields = {learningAnswers: comparableAnswers(state), learningUpdatedAt: FieldValue.serverTimestamp()};
  if (summaryExists) {
    tx.update(ref, fields);
  } else {
    tx.set(ref, fields, {merge: true});
  }
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

/** What the member's existing profile already says, reused for coverage. */
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
 * Marks a member who just finished profile onboarding as someone whose first
 * Picks wait for the onboarding questions (Q1-Q15). Create-only: it never
 * touches a member who already has state, and a failure leaves them unblocked.
 */
export async function markLearningRequired(db: Firestore, uid: string): Promise<void> {
  const ref = db.doc(learningStatePath(uid));
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists) return;
    writeLearningState(tx, db, uid, {...emptyLearningState(), required: true}, undefined);
  });
}

// ---------------------------------------------------------------------------
// Client payloads. Copy for both languages; no scoring metadata.
// ---------------------------------------------------------------------------

export interface QuestionPayload {
  id: string;
  version: number;
  answerType: string;
  category: string;
  dimension: string;
  prompt: {tr: string; en: string};
  options: Array<{id: string; label: {tr: string; en: string}}>;
  answerId: string | null;
}

/** A question as the client sees it, with the member's answer when `answered`. */
export function questionPayload(question: LearningQuestion, answerId: string | null): QuestionPayload {
  return {
    id: question.id,
    version: question.version,
    answerType: question.answerType,
    category: question.category,
    dimension: question.dimension,
    prompt: {...question.prompt},
    options: question.options.map((option) => ({id: option.id, label: {...option.label}})),
    answerId,
  };
}

/** Today's set for the client, each question with the member's answer (if any). */
export function dailySetPayload(set: DailySet, state: LearningState): QuestionPayload[] {
  return set.questions.map((ref) => {
    const question = learningQuestion(ref.id) as LearningQuestion;
    const answer = state.answers[ref.id];
    return questionPayload(question, answer?.version === ref.version ? answer.answerId : null);
  });
}
