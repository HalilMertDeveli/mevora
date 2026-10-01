import {createHash} from "node:crypto";
import {learningQuestion, type LearningQuestion} from "./catalog.js";
import {CORE, DAILY} from "./config.js";
import {CORE_SEQUENCE} from "./coreSequence.js";

/**
 * Which Core questions a member gets today. Pure and deterministic: the
 * member's own answers and the logical day are the only inputs. No calendar
 * rotation, no member id, device or time of day takes part.
 *
 *   onboarding   Q1-Q15 of the Core sequence, until every one is answered
 *   afterwards   the next five the member has not answered, once per day
 *
 * Because the order is the same for everyone and nobody can take more than
 * five a day, the questions two members share are always the whole prefix of
 * the one who has answered fewer.
 *
 * A day's set is frozen the first time the member answers or skips (the ids
 * are stored on their state), so answering Q16 does not slide Q21 into today.
 */

const DAY_MS = 86_400_000;

/** The logical day `nowMs` falls in, YYYY-MM-DD at the product offset. */
export function learningDayKey(nowMs: number): string {
  return new Date(nowMs + DAILY.utcOffsetMinutes * 60_000).toISOString().slice(0, 10);
}

/** When the logical day containing `nowMs` ends. */
export function nextLearningDayStartMs(nowMs: number): number {
  const offsetMs = DAILY.utcOffsetMinutes * 60_000;
  return Math.floor((nowMs + offsetMs) / DAY_MS) * DAY_MS + DAY_MS - offsetMs;
}

export function isDateKey(value: unknown): value is string {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
    !Number.isNaN(Date.parse(`${value}T00:00:00Z`));
}

/** `onboarding` is Q1-Q15; `core` is a day's five after that. */
export type DailySetKind = "onboarding" | "core";

export interface DailyQuestionRef {
  id: string;
  version: number;
}

export interface DailySet {
  dateKey: string;
  questionSetId: string;
  kind: DailySetKind;
  questions: DailyQuestionRef[];
}

/** What the schedule reads from a member's state. */
export interface CoreProgressFacts {
  answers: Record<string, {version: number}>;
  initialCompletedAtMs: number | null;
  daily: {
    dateKey: string | null;
    questionIds: string[] | null;
    kind: DailySetKind | null;
    completedAtMs: number | null;
  };
}

function activeQuestion(id: string): LearningQuestion | null {
  const question = learningQuestion(id);
  return question?.active ? question : null;
}

function activeQuestions(ids: readonly string[]): LearningQuestion[] {
  return ids.map(activeQuestion).filter((question): question is LearningQuestion => question !== null);
}

/** Every Core question still asked, in sequence order. A retired question keeps its place but is skipped. */
export function coreQuestions(): LearningQuestion[] {
  return activeQuestions(CORE_SEQUENCE);
}

/** Q1-Q15 as asked today: the first places of the sequence, minus any retired question. */
export function onboardingQuestions(): LearningQuestion[] {
  return activeQuestions(CORE_SEQUENCE.slice(0, CORE.onboardingCount));
}

function isAnswered(facts: CoreProgressFacts, question: LearningQuestion): boolean {
  return facts.answers[question.id]?.version === question.version;
}

/**
 * Onboarding is behind a member once they completed a first set, or — for
 * state that predates the Core sequence — once Q1-Q15 are all answered.
 */
export function hasFinishedOnboarding(facts: CoreProgressFacts): boolean {
  return facts.initialCompletedAtMs !== null ||
    onboardingQuestions().every((question) => isAnswered(facts, question));
}

/** How far through the Core sequence the member is. */
export function coreProgress(facts: CoreProgressFacts): {answered: number; total: number; exhausted: boolean} {
  const questions = coreQuestions();
  const answered = questions.filter((question) => isAnswered(facts, question)).length;
  return {answered, total: questions.length, exhausted: answered >= questions.length};
}

export function questionSetIdFor(kind: DailySetKind, dateKey: string, questions: DailyQuestionRef[]): string {
  if (questions.length === 0) return `${kind}-${dateKey}-none`;
  const digest = createHash("sha1")
    .update(questions.map((ref) => `${ref.id}@${ref.version}`).join(","))
    .digest("hex")
    .slice(0, 10);
  return `${kind}-${dateKey}-${digest}`;
}

function buildSet(kind: DailySetKind, dateKey: string, questions: LearningQuestion[]): DailySet {
  const refs = questions.map((question) => ({id: question.id, version: question.version}));
  return {dateKey, kind, questions: refs, questionSetId: questionSetIdFor(kind, dateKey, refs)};
}

/**
 * The member's set for `dateKey`.
 *
 * Already touched today: the frozen ids, minus any question retired since.
 * Otherwise it is derived from the answers: what is left of Q1-Q15 while
 * onboarding is open, else the first `CORE.dailyCount` unanswered questions
 * in sequence order. "First unanswered" rather than a counter, so answers
 * given before the sequence existed fill their own places and nothing is
 * asked twice.
 *
 * An empty set means there is nothing to ask today: the Core sequence is
 * finished, or the day was completed under the earlier calendar schedule.
 */
export function memberDailySet(facts: CoreProgressFacts, dateKey: string): DailySet {
  const touchedToday = facts.daily.dateKey === dateKey;
  if (touchedToday && facts.daily.questionIds) {
    return buildSet(facts.daily.kind ?? "core", dateKey, activeQuestions(facts.daily.questionIds));
  }
  if (touchedToday && facts.daily.completedAtMs !== null) {
    return buildSet("core", dateKey, []);
  }
  if (!hasFinishedOnboarding(facts)) {
    return buildSet("onboarding", dateKey, onboardingQuestions().filter((question) => !isAnswered(facts, question)));
  }
  const open = coreQuestions().filter((question) => !isAnswered(facts, question));
  return buildSet("core", dateKey, open.slice(0, CORE.dailyCount));
}
